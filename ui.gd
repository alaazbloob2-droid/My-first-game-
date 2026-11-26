extends CanvasLayer
# ui.gd - HUD, main menu, promotion / respawn pop-ups and the settings window.
# Everything is built once from Control nodes (retained mode). main.gd pushes values in at
# ~10 Hz through refresh(); nothing here redraws every frame except the kill feed fade.

signal play_pressed(nick: String, ship_id: String)
signal ship_picked(ship_id: String, mode: String)
signal slot_clicked(idx: int)
signal ability_clicked(idx: int)
signal setting_changed(key: String)
signal exit_requested
signal host_requested
signal join_requested(ip: String)
signal match_picked(ip: String)

const D := preload("res://data.gd")
const SettingsScript := preload("res://settings.gd")

const GAME_TITLE_A := "NAVAL"
const GAME_TITLE_B := ".IO"
const TAGLINE := "Sink ships. Collect crates. Climb through ten tiers of naval history."

const PANEL_BG := Color(0.03, 0.08, 0.15, 0.78)
const PANEL_BORDER := Color(1, 1, 1, 0.10)
const ACCENT := Color(0.13, 0.52, 0.96)
const ACCENT_HI := Color(0.30, 0.65, 1.0)
const GOOD := Color(0.30, 0.85, 0.45)
const WARN := Color(0.98, 0.76, 0.25)
const BAD := Color(0.95, 0.35, 0.30)
const TEXT := Color(1, 1, 1, 0.95)
const TEXT_DIM := Color(1, 1, 1, 0.62)

var S: SettingsScript
var settings_open := false
var map_isl_pos := PackedVector2Array()
var map_isl_r := PackedFloat32Array()
var map_world := 3000.0
var map: Dictionary = {}

var root: Control
var menu_root: Control
var hud_root: Control
var respawn_root: Control
var levelup_root: Control
var settings_root: Control
var name_edit: LineEdit
var play_btn: Button
var loading := 0.0
var join_root: Control
var join_ip_edit: LineEdit
var join_err: Label
var match_list: VBoxContainer
var match_msg: Label
var match_rows: Array = []
var host_addr_lbl: Label
var leave_btn: Button
var login_nick: LineEdit

var lbl_class: Label
var lbl_level: Label
var lbl_score: Label
var lbl_next: Label
var lbl_hp: Label
var lbl_fps: Label
var lbl_ctrl: Label
var lbl_winfo: Label
var lbl_hint: Label
var lbl_status: Label
var lbl_prof: Label
var bar_xp: ProgressBar
var bar_hp: ProgressBar
var bar_thr: ProgressBar
var hp_fill_sb: StyleBoxFlat
var lb_rows: Array = []
var map_panel: Control
var map_ctrl: Control
var feed_box: VBoxContainer
var feed: Array = []
var toast_lbl: Label
var toast_tween: Tween
var w_row: HBoxContainer
var ab_row: HBoxContainer
var w_slots: Array = []
var ab_slots: Array = []
var w_info: Array = []
var sel_idx := 0
var air_panel: Control
var air_title: Label
var air_state: Label
var air_bar: ProgressBar
var promo_banner: Button
var promo_panel: Control

var lu_title: Label
var lu_cards: HBoxContainer
var rs_title: Label
var rs_sub: Label
var rs_stats: Label
var rs_demote: Label
var rs_cards: HBoxContainer

var menu_ship_id := "pt_boat"
var menu_cards: Dictionary = {}
var menu_tier := 1
var profile_lbl: Label
var rank_lbl: Label
var meta_bar: ProgressBar
var ranked_btn: Button
var tier_row: HBoxContainer
var fleet_grid: GridContainer
var flash_rect: ColorRect
var lowhp_rect: ColorRect
var flash_tween: Tween
var tier_lbl: Label
var warn_lbl: Label
var map_zone := PackedVector2Array()
var set_ctrls: Dictionary = {}
var rebind_action := ""
var rebind_btn: Button
var key_btns: Dictionary = {}
var last_board_sig := ""
var game = null
var in_battle := false
var guest_mode := false
var page := "home"
var pages: Dictionary = {}
var nav_btns: Dictionary = {}
var page_box: Control
var login_root: Control
var login_pin: LineEdit
var login_err: Label
var results_root: Control
var res_box: VBoxContainer
var res_ri := 0
var badge_ctl: Control
var prof_ri := 0
var prof_d: Dictionary = {}
var paint_row: HBoxContainer
var rank_box: VBoxContainer
var mission_box: VBoxContainer
var bp_grid: GridContainer
var fleet_detail: VBoxContainer
var fleet_did := ""
var exit_btn: Button

# ---------------- Setup ----------------

func setup(settings: SettingsScript) -> void:
	S = settings
	layer = 10
	var full := Control.new()
	full.mouse_filter = Control.MOUSE_FILTER_IGNORE
	full.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(full)
	full.resized.connect(_apply_ui_scale)
	root = Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var th := Theme.new()
	th.default_font_size = 14
	root.theme = th
	full.add_child(root)
	_build_hud()
	_build_menu()
	_build_levelup()
	_build_respawn()
	_build_settings()
	warn_lbl = _label(root, "RETURN TO THE WARZONE!", 26, BAD)
	warn_lbl.add_theme_constant_override("outline_size", 8)
	warn_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	warn_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warn_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect(warn_lbl, 0, 0, 0, 0, 0, 84, 0, 130)

	# screen effects: red hit flash + low-health pulse
	flash_rect = ColorRect.new()
	flash_rect.color = Color(0.72, 0.06, 0.05, 1.0)
	flash_rect.modulate.a = 0.0
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash_rect)
	flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lowhp_rect = ColorRect.new()
	lowhp_rect.color = Color(0.80, 0.08, 0.06, 0.22)
	lowhp_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lowhp_rect.visible = false
	root.add_child(lowhp_rect)
	lowhp_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	warn_lbl.visible = false
	_apply_ui_scale()

func _apply_ui_scale() -> void:
	if root == null or root.get_parent() == null:
		return
	var vs: Vector2 = root.get_parent().size
	if vs.y <= 1.0:
		return
	var sc := clampf(S.f("ui_scale"), 0.6, 2.5) * clampf(vs.y / 720.0, 0.75, 2.2)
	root.scale = Vector2(sc, sc)
	root.size = vs / sc
	root.position = Vector2.ZERO

func _process(dt: float) -> void:
	if feed.is_empty():
		return
	var i := feed.size() - 1
	while i >= 0:
		var e: Dictionary = feed[i]
		e["t"] = float(e["t"]) - dt
		var lbl: Label = e["label"]
		if float(e["t"]) <= 0.0:
			lbl.queue_free()
			feed.remove_at(i)
		elif float(e["t"]) < 1.0:
			lbl.modulate.a = float(e["t"])
		i -= 1

func _input(e: InputEvent) -> void:
	if rebind_action == "":
		return
	if e is InputEventKey:
		var k: InputEventKey = e
		if not k.pressed:
			return
		if k.keycode == KEY_ESCAPE:
			rebind_btn.text = OS.get_keycode_string(S.key(rebind_action))
		else:
			S.keys[rebind_action] = int(k.keycode)
			rebind_btn.text = OS.get_keycode_string(k.keycode)
			_update_hint()
			_rebuild_ability_keys()
		rebind_action = ""
		get_viewport().set_input_as_handled()

# ---------------- Small builders ----------------

func _rect(c: Control, al: float, at: float, ar: float, ab: float, ol: float, ot: float, orr: float, ob: float) -> void:
	c.anchor_left = al
	c.anchor_top = at
	c.anchor_right = ar
	c.anchor_bottom = ab
	c.offset_left = ol
	c.offset_top = ot
	c.offset_right = orr
	c.offset_bottom = ob

func _panel(parent: Node, bg: Color = PANEL_BG, pad: float = 12.0, radius: int = 10) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(pad)
	sb.border_color = PANEL_BORDER
	sb.set_border_width_all(1)
	sb.shadow_color = Color(0, 0, 0, 0.25)
	sb.shadow_size = 6
	p.add_theme_stylebox_override("panel", sb)
	if parent != null:
		parent.add_child(p)
	return p

func _label(parent: Node, text: String, size: int = 14, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l

func _bar(parent: Node, h: float, fill: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.min_value = 0.0
	b.max_value = 1.0
	b.step = 0.001
	b.custom_minimum_size = Vector2(0, h)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.10)
	bg.set_corner_radius_all(int(h * 0.5))
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	fg.set_corner_radius_all(int(h * 0.5))
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)
	b.set_meta("fill_sb", fg)
	parent.add_child(b)
	return b

func _ignore_mouse(n: Node) -> void:
	if n is Control:
		var c: Control = n
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for ch in n.get_children():
		_ignore_mouse(ch)

func _btn_style(col: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(8)
	return sb

func _make_button(parent: Node, text: String, size: int, min_size: Vector2, col: Color = ACCENT) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_stylebox_override("normal", _btn_style(col))
	b.add_theme_stylebox_override("hover", _btn_style(col.lightened(0.18)))
	b.add_theme_stylebox_override("pressed", _btn_style(col.darkened(0.2)))
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	parent.add_child(b)
	return b

func _clear(n: Node) -> void:
	for ch in n.get_children():
		n.remove_child(ch)
		ch.queue_free()

func _key_name(action: String) -> String:
	return OS.get_keycode_string(S.key(action))

# ---------------- Icons (drawn procedurally, no image files) ----------------

func _draw_icon(c: Control, ic: String, ctr: Vector2) -> void:
	match ic:
		"bullet":
			for i in 3:
				var x := ctr.x - 10.0 + float(i) * 10.0
				c.draw_line(Vector2(x, ctr.y + 7.0), Vector2(x, ctr.y - 3.0), Color(0.85, 0.7, 0.3), 4.0)
				c.draw_circle(Vector2(x, ctr.y - 5.0), 2.4, Color(1.0, 0.85, 0.4))
		"shell_s", "shell_m", "shell_l":
			var k := 0.75
			if ic == "shell_m":
				k = 1.05
			elif ic == "shell_l":
				k = 1.4
			c.draw_rect(Rect2(ctr + Vector2(-15.0, -5.0) * k, Vector2(19.0, 10.0) * k), Color(0.80, 0.62, 0.30))
			c.draw_colored_polygon(PackedVector2Array([ctr + Vector2(4.0, -5.0) * k, ctr + Vector2(15.0, 0.0) * k, ctr + Vector2(4.0, 5.0) * k]), Color(0.72, 0.74, 0.78))
			c.draw_rect(Rect2(ctr + Vector2(1.0, -5.0) * k, Vector2(2.0, 10.0) * k), Color(0.55, 0.38, 0.15))
		"torp":
			c.draw_rect(Rect2(ctr + Vector2(-18.0, -4.0), Vector2(30.0, 8.0)), Color(0.82, 0.87, 0.93))
			c.draw_circle(ctr + Vector2(12.0, 0.0), 4.0, Color(0.95, 0.3, 0.3))
			c.draw_line(ctr + Vector2(-18.0, -4.0), ctr + Vector2(-23.0, -9.0), Color(0.82, 0.87, 0.93), 2.0)
			c.draw_line(ctr + Vector2(-18.0, 4.0), ctr + Vector2(-23.0, 9.0), Color(0.82, 0.87, 0.93), 2.0)
		"missile":
			c.draw_rect(Rect2(ctr + Vector2(-17.0, -3.5), Vector2(26.0, 7.0)), Color(0.90, 0.92, 0.95))
			c.draw_colored_polygon(PackedVector2Array([ctr + Vector2(9.0, -3.5), ctr + Vector2(18.0, 0.0), ctr + Vector2(9.0, 3.5)]), Color(0.85, 0.28, 0.22))
			c.draw_colored_polygon(PackedVector2Array([ctr + Vector2(-17.0, -3.5), ctr + Vector2(-12.0, -3.5), ctr + Vector2(-17.0, -9.0)]), Color(0.6, 0.63, 0.68))
			c.draw_colored_polygon(PackedVector2Array([ctr + Vector2(-17.0, 3.5), ctr + Vector2(-12.0, 3.5), ctr + Vector2(-17.0, 9.0)]), Color(0.6, 0.63, 0.68))
			c.draw_line(ctr + Vector2(-17.0, 0.0), ctr + Vector2(-23.0, 0.0), Color(1.0, 0.65, 0.2), 3.0)
		"missile_s":
			_icon_missile(c, ctr, Color(0.92, 0.93, 0.95), Color(0.85, 0.20, 0.18), 11.0, Color(0.6, 0.63, 0.68), 7.0)
		"missile_h":
			_icon_missile(c, ctr, Color(0.38, 0.42, 0.48), Color(0.85, 0.86, 0.88), 19.0, Color(0.28, 0.31, 0.36), 12.0)
		"cruise":
			_icon_missile(c, ctr, Color(0.93, 0.90, 0.80), Color(0.40, 0.42, 0.45), 18.0, Color(0.30, 0.32, 0.35), 15.0)
		"rocket_h":
			for i in 2:
				var y2 := ctr.y - 6.0 + float(i) * 12.0
				c.draw_rect(Rect2(Vector2(ctr.x - 14.0, y2 - 3.0), Vector2(22.0, 6.0)), Color(0.50, 0.45, 0.28))
				c.draw_rect(Rect2(Vector2(ctr.x - 2.0, y2 - 3.0), Vector2(3.0, 6.0)), Color(0.95, 0.80, 0.20))
				c.draw_colored_polygon(PackedVector2Array([Vector2(ctr.x + 8.0, y2 - 3.0), Vector2(ctr.x + 14.0, y2), Vector2(ctr.x + 8.0, y2 + 3.0)]), Color(0.80, 0.20, 0.18))
				c.draw_line(Vector2(ctr.x - 14.0, y2), Vector2(ctr.x - 19.0, y2), Color(1.0, 0.65, 0.2), 2.0)
		"rocket":
			for i in 3:
				var y := ctr.y - 9.0 + float(i) * 9.0
				c.draw_rect(Rect2(Vector2(ctr.x - 12.0, y - 2.0), Vector2(18.0, 4.0)), Color(0.78, 0.8, 0.82))
				c.draw_circle(Vector2(ctr.x + 6.0, y), 2.2, Color(0.9, 0.3, 0.25))
				c.draw_line(Vector2(ctr.x - 12.0, y), Vector2(ctr.x - 17.0, y), Color(1.0, 0.65, 0.2), 2.0)
		"mine":
			c.draw_circle(ctr, 8.0, Color(0.18, 0.2, 0.22))
			for i in 8:
				var d := Vector2.from_angle(float(i) * PI * 0.25)
				c.draw_line(ctr + d * 8.0, ctr + d * 13.0, Color(0.7, 0.72, 0.75), 2.5)
			c.draw_circle(ctr, 2.5, Color(0.9, 0.25, 0.2))
		"bomb":
			c.draw_circle(ctr + Vector2(-2.0, 0.0), 8.0, Color(0.25, 0.27, 0.3))
			c.draw_colored_polygon(PackedVector2Array([ctr + Vector2(5.0, -4.0), ctr + Vector2(16.0, 0.0), ctr + Vector2(5.0, 4.0)]), Color(0.25, 0.27, 0.3))
			c.draw_line(ctr + Vector2(12.0, -5.0), ctr + Vector2(18.0, -9.0), Color(0.6, 0.63, 0.68), 2.0)
			c.draw_line(ctr + Vector2(12.0, 5.0), ctr + Vector2(18.0, 9.0), Color(0.6, 0.63, 0.68), 2.0)
		"mark":
			c.draw_arc(ctr, 10.0, 0.0, TAU, 20, Color(1.0, 0.4, 0.35), 2.5)
			c.draw_line(ctr + Vector2(-15.0, 0.0), ctr + Vector2(-6.0, 0.0), Color(1.0, 0.4, 0.35), 2.5)
			c.draw_line(ctr + Vector2(15.0, 0.0), ctr + Vector2(6.0, 0.0), Color(1.0, 0.4, 0.35), 2.5)
			c.draw_line(ctr + Vector2(0.0, -15.0), ctr + Vector2(0.0, -6.0), Color(1.0, 0.4, 0.35), 2.5)
			c.draw_line(ctr + Vector2(0.0, 15.0), ctr + Vector2(0.0, 6.0), Color(1.0, 0.4, 0.35), 2.5)

# ---------------- HUD ----------------

func _build_hud() -> void:
	hud_root = Control.new()
	root.add_child(hud_root)
	hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	leave_btn = _make_button(hud_root, "LEAVE BATTLE", 13, Vector2(150, 32), Color(0.62, 0.28, 0.18))
	_rect(leave_btn, 0.5, 0, 0.5, 0, -78, 10, 78, 42)
	leave_btn.visible = false
	leave_btn.pressed.connect(_exit_battle)

	# --- status panel (top-left)
	var st := _panel(hud_root)
	_rect(st, 0, 0, 0, 0, 16, 16, 16 + 270, 17)
	st.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	st.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	lbl_class = _label(head, "Patrol Boat", 18)
	lbl_class.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_class.clip_text = true
	lbl_level = _label(head, "Tier I", 14, WARN)
	lbl_score = _label(v, "Score 0", 15)
	bar_xp = _bar(v, 8.0, ACCENT_HI)
	lbl_next = _label(v, "", 12, TEXT_DIM)
	var hr := HBoxContainer.new()
	hr.add_theme_constant_override("separation", 8)
	v.add_child(hr)
	_label(hr, "HULL", 11, TEXT_DIM)
	bar_hp = _bar(hr, 12.0, GOOD)
	bar_hp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_hp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hp_fill_sb = bar_hp.get_meta("fill_sb")
	lbl_hp = _label(hr, "", 11, TEXT_DIM)
	var tr := HBoxContainer.new()
	tr.add_theme_constant_override("separation", 8)
	v.add_child(tr)
	_label(tr, "SPEED", 11, TEXT_DIM)
	bar_thr = _bar(tr, 6.0, ACCENT)
	bar_thr.min_value = -0.3
	bar_thr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_thr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lbl_status = _label(v, "", 14, Color(1.0, 0.55, 0.2))
	lbl_status.visible = false

	# --- aircraft panel (under the status panel)
	var ap := _panel(hud_root, PANEL_BG, 10.0)
	air_panel = ap
	_rect(ap, 0, 0, 0, 0, 16, 190, 16 + 270, 191)
	ap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var av := VBoxContainer.new()
	av.add_theme_constant_override("separation", 4)
	ap.add_child(av)
	air_title = _label(av, "", 14)
	air_bar = _bar(av, 7.0, GOOD)
	air_state = _label(av, "", 12, TEXT_DIM)
	ap.visible = false

	# --- leaderboard (top-right)
	var lb := _panel(hud_root)
	_rect(lb, 1, 0, 1, 0, -16 - 230, 16, -16, 17)
	lb.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 3)
	lb.add_child(lv)
	_label(lv, "Leaderboard", 16)
	for i in 8:
		var row := HBoxContainer.new()
		lv.add_child(row)
		var rn := _label(row, "", 13)
		rn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rn.clip_text = true
		var rs := _label(row, "", 13, TEXT_DIM)
		rs.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lb_rows.append([row, rn, rs])

	# --- armament bar (bottom-centre): abilities | weapons
	var bp := _panel(hud_root, PANEL_BG, 8.0)
	_rect(bp, 0.5, 1, 0.5, 1, -80, -16 - 110, 80, -16)
	bp.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bp.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 4)
	bp.add_child(bv)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 10)
	bv.add_child(brow)
	ab_row = HBoxContainer.new()
	ab_row.add_theme_constant_override("separation", 6)
	brow.add_child(ab_row)
	var sep := VSeparator.new()
	brow.add_child(sep)
	w_row = HBoxContainer.new()
	w_row.add_theme_constant_override("separation", 6)
	brow.add_child(w_row)
	lbl_winfo = _label(bv, "", 12, TEXT_DIM)
	lbl_winfo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# --- minimap (bottom-right)
	map_panel = _panel(hud_root, PANEL_BG, 6.0)
	_rect(map_panel, 1, 1, 1, 1, -16 - 212, -16 - 212, -16, -16)
	map_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	map_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	map_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_ctrl = Control.new()
	map_ctrl.custom_minimum_size = Vector2(200, 200)
	map_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_panel.add_child(map_ctrl)
	map_ctrl.draw.connect(_draw_minimap)

	# --- kill feed + hint (bottom-left)
	feed_box = VBoxContainer.new()
	feed_box.add_theme_constant_override("separation", 2)
	hud_root.add_child(feed_box)
	_rect(feed_box, 0, 1, 0, 1, 16, -44, 16 + 360, -40)
	feed_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	lbl_hint = _label(hud_root, "", 12, TEXT_DIM)
	_rect(lbl_hint, 0, 1, 0, 1, 16, -30, 16 + 640, -12)
	lbl_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN

	# --- fps + aircraft control banner (top-centre)
	lbl_fps = _label(hud_root, "", 12, TEXT_DIM)
	lbl_fps.visible = false
	lbl_fps.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rect(lbl_fps, 0.5, 0, 0.5, 0, -150, 10, 150, 28)
	lbl_ctrl = _label(hud_root, "", 15, Color(0.6, 0.95, 1.0))
	lbl_ctrl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_ctrl.add_theme_constant_override("outline_size", 5)
	lbl_ctrl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_rect(lbl_ctrl, 0.5, 0, 0.5, 0, -250, 30, 250, 50)

	# --- toast (top-centre, below)
	toast_lbl = _label(hud_root, "", 26, WARN)
	toast_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_lbl.add_theme_constant_override("outline_size", 6)
	toast_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	toast_lbl.modulate.a = 0.0
	_rect(toast_lbl, 0.5, 0, 0.5, 0, -300, 62, 300, 100)

	# --- collapsed promotion banner
	promo_banner = _make_button(hud_root, "", 15, Vector2(300, 34), Color(0.85, 0.55, 0.1))
	_rect(promo_banner, 0.5, 0, 0.5, 0, -150, 104, 150, 138)
	promo_banner.visible = false
	promo_banner.pressed.connect(expand_levelup)

	# only the interactive pieces below should catch the mouse
	for ch in [st, ap, lb, map_panel]:
		_ignore_mouse(ch)
	_update_hint()

func _update_hint() -> void:
	if lbl_hint == null:
		return
	lbl_hint.text = "%s/%s throttle   %s/%s steer   LMB/%s fire   1-9 weapon   %s/%s ability   %s aircraft   Wheel zoom   Esc settings" % [
		_key_name("up"), _key_name("down"), _key_name("left"), _key_name("right"), _key_name("fire"),
		_key_name("ab1"), _key_name("ab2"), _key_name("air")]

# ---- dynamic loadout (weapon slots / ability slots) ----

func set_loadout(wl: Array, al: Array, air_name: String, in_air: bool) -> void:
	_clear(w_row)
	w_slots.clear()
	w_info = wl
	for i in wl.size():
		var w: Dictionary = wl[i]
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 1)
		w_row.add_child(box)
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(70, 56)
		slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		box.add_child(slot)
		slot.draw.connect(_draw_slot.bind(slot, str(w["ic"]), i))
		slot.gui_input.connect(_slot_input.bind(i))
		var cd := ColorRect.new()
		cd.color = Color(0, 0, 0, 0.62)
		cd.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cd.position = Vector2(0, 0)
		cd.size = Vector2(70, 0)
		slot.add_child(cd)
		if bool(w.get("aa", false)):
			var aat := _label(slot, "AA", 10, Color(0.5, 0.95, 1.0))
			aat.position = Vector2(48, 2)
			aat.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var kl := _label(slot, str(i + 1), 12, Color(1, 1, 1, 0.9))
		kl.position = Vector2(6, 2)
		kl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cl := _label(slot, "", 11, WARN)
		cl.position = Vector2(34, 40)
		cl.size = Vector2(34, 14)
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var nl := _label(box, str(w["n"]), 9, TEXT_DIM)
		nl.custom_minimum_size = Vector2(70, 0)
		nl.clip_text = true
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		w_slots.append({"slot": slot, "cd": cd, "cnt": cl})
	_clear(ab_row)
	ab_slots.clear()
	for i in al.size():
		var a: Dictionary = al[i]
		var box2 := VBoxContainer.new()
		box2.add_theme_constant_override("separation", 1)
		ab_row.add_child(box2)
		var slot2 := Control.new()
		slot2.custom_minimum_size = Vector2(52, 56)
		slot2.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		box2.add_child(slot2)
		slot2.set_meta("on", false)
		slot2.set_meta("key", "ab%d" % (i + 1))
		slot2.set_meta("glyph", str(a["n"]).substr(0, 1))
		slot2.draw.connect(_draw_ab_slot.bind(slot2))
		slot2.gui_input.connect(_ab_input.bind(i))
		slot2.tooltip_text = "%s - %s" % [str(a["n"]), str(a["desc"])]
		var cd2 := ColorRect.new()
		cd2.color = Color(0, 0, 0, 0.62)
		cd2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cd2.size = Vector2(52, 0)
		slot2.add_child(cd2)
		var nl2 := _label(box2, str(a["n"]), 9, TEXT_DIM)
		nl2.custom_minimum_size = Vector2(52, 0)
		nl2.clip_text = true
		nl2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ab_slots.append({"slot": slot2, "cd": cd2})
	ab_row.get_parent().get_child(1).visible = al.size() > 0
	ab_row.visible = al.size() > 0
	air_panel.visible = air_name != ""
	_update_hint()

func _rebuild_ability_keys() -> void:
	for a in ab_slots:
		var s: Control = a["slot"]
		s.queue_redraw()

func set_selected(idx: int) -> void:
	sel_idx = idx
	for w in w_slots:
		var s: Control = w["slot"]
		s.queue_redraw()
	if idx >= 0 and idx < w_info.size():
		var wi: Dictionary = w_info[idx]
		lbl_winfo.text = "%s  -  damage %d, range %d%s" % [str(wi["n"]), int(float(wi["dmg"])), int(float(wi["rng"])), "  (anti-aircraft)" if bool(wi.get("aa", false)) else ""]
		if float(wi["rng"]) <= 0.0:
			lbl_winfo.text = str(wi["n"])
	else:
		lbl_winfo.text = ""

func _slot_input(e: InputEvent, idx: int) -> void:
	if e is InputEventMouseButton:
		var mb: InputEventMouseButton = e
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			slot_clicked.emit(idx)

func _ab_input(e: InputEvent, idx: int) -> void:
	if e is InputEventMouseButton:
		var mb: InputEventMouseButton = e
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			ability_clicked.emit(idx)

func _draw_slot(c: Control, ic: String, idx: int) -> void:
	var sb := StyleBoxFlat.new()
	var selected := idx == sel_idx
	sb.bg_color = Color(0.13, 0.30, 0.52, 0.55) if selected else Color(1, 1, 1, 0.08)
	sb.set_corner_radius_all(8)
	sb.border_color = ACCENT_HI if selected else Color(1, 1, 1, 0.18)
	sb.set_border_width_all(2 if selected else 1)
	c.draw_style_box(sb, Rect2(Vector2.ZERO, Vector2(70, 56)))
	_draw_icon(c, ic, Vector2(35, 27))

func _draw_ab_slot(c: Control) -> void:
	var on := bool(c.get_meta("on"))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.15, 0.55, 0.30, 0.6) if on else Color(1, 1, 1, 0.08)
	sb.set_corner_radius_all(26)
	sb.border_color = GOOD if on else Color(1, 1, 1, 0.22)
	sb.set_border_width_all(2)
	c.draw_style_box(sb, Rect2(Vector2(0, 2), Vector2(52, 52)))
	var font := ThemeDB.fallback_font
	c.draw_string(font, Vector2(0, 33), str(c.get_meta("glyph")), HORIZONTAL_ALIGNMENT_CENTER, 52.0, 22, Color(1, 1, 1, 0.9))
	c.draw_string(font, Vector2(0, 14), OS.get_keycode_string(S.key(str(c.get_meta("key")))), HORIZONTAL_ALIGNMENT_CENTER, 52.0, 11, Color(1, 1, 1, 0.75))

# ---- minimap ----

func _draw_minimap() -> void:
	var m := map_ctrl
	var sz := m.size
	m.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.02, 0.10, 0.20, 0.85))
	var k := sz.x / (map_world * 2.0)
	var c := sz * 0.5
	for i in map_isl_pos.size():
		m.draw_circle(c + map_isl_pos[i] * k, maxf(2.0, map_isl_r[i] * k), Color(0.32, 0.62, 0.30))
	if map.is_empty():
		return
	var pp: Vector2 = map["pp"]
	if bool(map["alive"]):
		var det := float(map["det"])
		m.draw_arc(c + pp * k, det * k, 0.0, TAU, 32, Color(0.5, 0.85, 1.0, 0.22), 1.0)
		var av := float(map["air_vis"])
		if av > 0.0:
			var ap: Vector2 = map["air_pos"]
			m.draw_arc(c + ap * k, av * k, 0.0, TAU, 24, Color(0.5, 1.0, 0.8, 0.22), 1.0)
	var blips: PackedVector2Array = map["blips"]
	var bt: PackedInt32Array = map["blip_t"]
	for i in blips.size():
		m.draw_circle(c + blips[i] * k, 2.0 + float(bt[i]) * 0.35, BAD)
	if bool(map["alive"]):
		var pa := float(map["pa"])
		var p: Vector2 = c + pp * k
		m.draw_colored_polygon(PackedVector2Array([Vector2(7, 0).rotated(pa) + p, Vector2(-4, 4).rotated(pa) + p, Vector2(-4, -4).rotated(pa) + p]), Color(0.55, 0.85, 1.0))
		if float(map["air_vis"]) > 0.0:
			var ap2: Vector2 = c + Vector2(map["air_pos"]) * k
			var aa := float(map["air_ang"])
			m.draw_colored_polygon(PackedVector2Array([Vector2(5, 0).rotated(aa) + ap2, Vector2(-3, 3).rotated(aa) + ap2, Vector2(-3, -3).rotated(aa) + ap2]), Color(0.5, 1.0, 0.8))
	if map_zone.size() > 3:
		var zp := PackedVector2Array()
		for q in map_zone:
			zp.append(c + q * k)
		zp.append(zp[0])
		m.draw_polyline(zp, Color(1, 0.35, 0.3, 0.9), 2.0)
	var ch: Vector2 = map["cam_pos"]
	var hv: Vector2 = map["view_half"]
	m.draw_rect(Rect2(c + (ch - hv) * k, hv * 2.0 * k), Color(1, 1, 1, 0.35), false, 1.0)
	m.draw_rect(Rect2(Vector2.ZERO, sz), Color(1, 0.3, 0.3, 0.6), false, 1.5)

# ---------------- Ship cards (used by menu, promotion and respawn windows) ----------------

func _draw_preview(c: Control, def: Dictionary) -> void:
	var sz := c.size
	var L := float(def["len"])
	var W := float(def["wid"])
	var st: Dictionary = D.STYLES[str(def["style"])]
	var pn := str(def["pal"])
	if pn == "":
		pn = str(st["pal"])
	var pal: Dictionary = D.PAL[pn]
	var sc := minf((sz.x - 10.0) / (L * 1.02), (sz.y - 4.0) / (W * 1.25))
	var ctr := sz * 0.5
	var hull := D.hull_pts(L, W, float(st["bow"]), float(st["bp"]), float(st["st"]))
	var pts := PackedVector2Array()
	for p in hull:
		pts.append(ctr + p * sc)
	var is_cv := str(def["style"]) == "cv"
	c.draw_colored_polygon(pts, pal["hull"])
	var dp := PackedVector2Array()
	for p in hull:
		dp.append(ctr + Vector2(p.x * 0.97, p.y * 0.8) * sc)
	c.draw_colored_polygon(dp, pal["deck"])
	if is_cv:
		var fd := PackedVector2Array([Vector2(-L * 0.5, -W * 0.55), Vector2(L * 0.4, -W * 0.55), Vector2(L * 0.5, -W * 0.28), Vector2(L * 0.5, W * 0.4), Vector2(L * 0.4, W * 0.55), Vector2(-L * 0.5, W * 0.55)])
		var fp := PackedVector2Array()
		for p in fd:
			fp.append(ctr + p * sc)
		c.draw_colored_polygon(fp, pal["deck"])
		c.draw_rect(Rect2(ctr + Vector2(L * 0.05, W * 0.39) * sc, Vector2(L * 0.1, W * 0.16) * sc), pal["sup"])
	c.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.03, 0.05, 0.08, 0.9), 1.2)
	for b in st["sup"]:
		c.draw_rect(Rect2(ctr + Vector2((float(b[0]) - float(b[1]) * 0.5) * L, -float(b[2]) * W * 0.5) * sc, Vector2(float(b[1]) * L, float(b[2]) * W) * sc), pal["sup"])
	for f in st["fun"]:
		c.draw_circle(ctr + Vector2(float(f) * L, 0.0) * sc, W * 0.14 * sc, Color(0.16, 0.17, 0.19))
	for g in def["weapons"]:
		var wd: Dictionary = D.WEAPONS[str(g["w"])]
		for m in g["m"]:
			var mp: Vector2 = ctr + Vector2(float(m["x"]) * L, float(m["y"]) * W) * sc
			if str(wd["vis"]) == "gun":
				var bl := float(wd["bl"])
				c.draw_line(mp, mp + Vector2.from_angle(0.0) * bl * sc * 0.9, Color(0.1, 0.11, 0.13), maxf(float(wd["bw"]) * sc * float(m["b"]), 1.2))
				c.draw_circle(mp, maxf(float(wd["bl"]) * 0.28 * sc, 1.5), Color(0.42, 0.45, 0.5))
			elif str(wd["vis"]) == "ciws":
				c.draw_circle(mp, maxf(2.6 * sc, 1.4), Color(0.85, 0.87, 0.89))
			else:
				c.draw_rect(Rect2(mp - Vector2(3.0, 2.0) * sc, Vector2(6.0, 4.0) * sc), Color(0.22, 0.25, 0.28))

func _stat_row(parent: Node, label: String, ratio: float, col: Color) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	parent.add_child(h)
	var l := _label(h, label, 10, TEXT_DIM)
	l.custom_minimum_size = Vector2(44, 0)
	var b := _bar(h, 7.0, col)
	b.value = clampf(ratio, 0.0, 1.0)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER

func _weapon_lines(def: Dictionary, max_lines: int) -> String:
	var lines: Array = []
	for g in def["weapons"]:
		var n := 0
		for m in g["m"]:
			n += int(m["b"])
		lines.append("%dx %s" % [n, str(D.WEAPONS[str(g["w"])]["n"])])
	if lines.size() > max_lines:
		lines = lines.slice(0, max_lines)
		lines.append("...")
	return "\n".join(lines)

func _ship_card(def: Dictionary, btn_text: String, cb: Callable, w: float, compact: bool) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(w, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.11, 0.19, 0.94)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(8)
	sb.border_color = Color(1, 1, 1, 0.14)
	sb.set_border_width_all(1)
	pc.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	pc.add_child(v)
	var pv := Control.new()
	pv.custom_minimum_size = Vector2(w - 16.0, 44.0 if compact else 60.0)
	pv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(pv)
	pv.draw.connect(_draw_preview.bind(pv, def))
	var nm := _label(v, str(def["name"]), 13 if compact else 14)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.custom_minimum_size = Vector2(w - 16.0, 0)
	_label(v, "Tier %s  |  %s" % [str(D.ROMAN[int(def["tier"]) - 1]), str(def["cls"])], 11, ACCENT_HI)
	if not compact:
		_stat_row(v, "HULL", float(def["hp"]) / 20000.0, GOOD)
		_stat_row(v, "SPEED", float(def["spd"]) / 250.0, ACCENT)
		_stat_row(v, "FIRE", D.dps(def) / 2200.0, BAD)
		_stat_row(v, "VISION", float(def["det"]) / 2300.0, WARN)
	var wl := _label(v, _weapon_lines(def, 4 if compact else 6), 11, TEXT)
	wl.custom_minimum_size = Vector2(w - 16.0, 0)
	wl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var abil: Array = []
	for a in def["abil"]:
		abil.append(str(D.ABILITIES[str(a)]["n"]))
	var al := _label(v, "Abilities: " + ", ".join(abil), 10, TEXT_DIM)
	al.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	al.custom_minimum_size = Vector2(w - 16.0, 0)
	if str(def["air"]) != "":
		var sqn := int(def.get("squad", 1))
		var ail := _label(v, "Aircraft: %s   (squad of %d)" % [str(D.AIR[str(def["air"])]["n"]), sqn], 10, Color(0.6, 0.95, 1.0))
		ail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ail.custom_minimum_size = Vector2(w - 16.0, 0)
	var subn := str(def.get("cls", ""))
	if subn == "Submarine":
		var sl := _label(v, "Can dive: press the Emergency Dive ability", 10, Color(0.6, 1.0, 0.85))
		sl.custom_minimum_size = Vector2(w - 16.0, 0)
	var b := _make_button(v, btn_text, 14, Vector2(0, 30))
	b.pressed.connect(cb)
	return pc

func _emit_pick(id: String, mode: String) -> void:
	ship_picked.emit(id, mode)

# ---------------- Promotion pop-up (top of the screen) ----------------

func _build_levelup() -> void:
	levelup_root = Control.new()
	levelup_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(levelup_root)
	levelup_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	promo_panel = _panel(levelup_root, Color(0.03, 0.08, 0.15, 0.94), 14.0, 14)
	_rect(promo_panel, 0.5, 0, 0.5, 0, -520, 12, 520, 13)
	promo_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	promo_panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	lu_title = _label(head, "PROMOTION", 22, WARN)
	lu_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var later := _make_button(head, "Later  (U to reopen)", 13, Vector2(170, 30), Color(0.3, 0.34, 0.4))
	later.pressed.connect(collapse_levelup)
	lu_cards = HBoxContainer.new()
	lu_cards.add_theme_constant_override("separation", 10)
	lu_cards.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(lu_cards)
	levelup_root.visible = false

func show_levelup(tier: int, defs: Array) -> void:
	lu_title.text = "PROMOTION  -  choose your Tier %s ship" % str(D.ROMAN[tier - 1])
	_clear(lu_cards)
	for def in defs:
		var d: Dictionary = def
		lu_cards.add_child(_ship_card(d, "Command", _emit_pick.bind(str(d["id"]), "levelup"), 188.0, false))
	levelup_root.visible = true
	promo_panel.visible = true
	promo_banner.visible = false
	promo_banner.text = "Promotion available  (%s)" % _key_name("upgrade")

func collapse_levelup() -> void:
	promo_panel.visible = false
	promo_banner.visible = true
	audio_click()

func expand_levelup() -> void:
	if lu_cards.get_child_count() == 0:
		return
	promo_panel.visible = true
	promo_banner.visible = false
	levelup_root.visible = true

func hide_levelup() -> void:
	levelup_root.visible = false
	promo_banner.visible = false
	_clear(lu_cards)

func audio_click() -> void:
	pass

# ---------------- Respawn pop-up ----------------

func _build_respawn() -> void:
	respawn_root = Control.new()
	root.add_child(respawn_root)
	respawn_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	respawn_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dim := ColorRect.new()
	dim.color = Color(0.1, 0.0, 0.02, 0.45)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	respawn_root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	respawn_root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var card := _panel(center, Color(0.03, 0.08, 0.15, 0.95), 20.0, 14)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	card.add_child(v)
	rs_title = _label(v, "You were sunk!", 34, Color(1, 0.8, 0.8))
	rs_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rs_sub = _label(v, "", 15, TEXT_DIM)
	rs_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rs_stats = _label(v, "", 16, TEXT)
	rs_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rs_demote = _label(v, "", 16, WARN)
	rs_demote.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rs_cards = HBoxContainer.new()
	rs_cards.add_theme_constant_override("separation", 10)
	rs_cards.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(rs_cards)
	respawn_root.visible = false

func show_respawn(info: Dictionary, defs: Array) -> void:
	rs_sub.text = "Sunk by %s while commanding the %s" % [str(info["killer"]), str(info["ship"])]
	rs_stats.text = "Score %d     Ships sunk %d" % [int(info["score"]), int(info["kills"])]
	var from_t := int(info["from"])
	var to_t := int(info["to"])
	var pct := int(float(info["progress"]) * 100.0)
	if to_t >= from_t:
		rs_demote.text = "You stay at Tier %s. Choose your ship:" % str(D.ROMAN[to_t - 1])
	else:
		rs_demote.text = "Demoted from Tier %s to Tier %s (you were %d%% of the way to promotion). Choose your ship:" % [str(D.ROMAN[from_t - 1]), str(D.ROMAN[to_t - 1]), pct]
	_clear(rs_cards)
	for def in defs:
		var d: Dictionary = def
		rs_cards.add_child(_ship_card(d, "Deploy", _emit_pick.bind(str(d["id"]), "respawn"), 188.0, false))
	respawn_root.visible = true

func hide_respawn() -> void:
	respawn_root.visible = false
	_clear(rs_cards)

# ---------------- Main menu ----------------

# ---------------- Main menu: multi-page command port ----------------

func _build_menu() -> void:
	menu_root = Control.new()
	root.add_child(menu_root)
	menu_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.04, 0.10, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var band := ColorRect.new()
	band.color = Color(0.02, 0.10, 0.18, 0.4)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_root.add_child(band)
	band.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# top bar: emblem + wordmark on the left, page navigation on the right
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	menu_root.add_child(top)
	_rect(top, 0, 0, 1, 0, 46, 18, -46, 88)
	var emblem := Control.new()
	emblem.custom_minimum_size = Vector2(72, 72)
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	emblem.draw.connect(_draw_logo.bind(emblem, 1.0))
	top.add_child(emblem)
	var title_box := VBoxContainer.new()
	title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(title_box)
	var word := HBoxContainer.new()
	word.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_box.add_child(word)
	var wa := _label(word, GAME_TITLE_A, 32, Color.WHITE)
	var wb := _label(word, GAME_TITLE_B, 32, Color(0.86, 0.69, 0.22))
	for t in [wa, wb]:
		t.add_theme_constant_override("outline_size", 6)
		t.add_theme_color_override("font_outline_color", Color(0, 0.05, 0.15, 0.7))
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sub := _label(title_box, TAGLINE, 12, TEXT_DIM)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(spacer)
	for pg in [["home", "PORT"], ["profile", "PROFILE"], ["fleet", "FLEET"], ["progress", "BATTLE PASS"], ["configs", "SETTINGS"]]:
		var nb := _make_button(top, pg[1], 15, Vector2(150, 46), Color(0.14, 0.22, 0.34))
		nb.pressed.connect(_goto.bind(pg[0]))
		nav_btns[pg[0]] = nb

	page_box = Control.new()
	page_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_root.add_child(page_box)
	_rect(page_box, 0, 0, 1, 1, 46, 106, -46, -66)

	pages["home"] = _page_home()
	pages["profile"] = _page_profile()
	pages["fleet"] = _page_fleet()
	pages["progress"] = _page_progress()
	pages["configs"] = _page_configs()

	var hint := _label(menu_root, "W/S throttle    A/D steer    Mouse: aim    Click/Space: fire    1-9: weapons    Q/E/R: abilities    V: aircraft    Esc: settings", 13, TEXT_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect(hint, 0.5, 1, 0.5, 1, -430, -32, 430, -10)

	_build_login()
	_build_join()
	_build_results()
	_goto("home", true)

func _goto(pg: String, silent: bool = false) -> void:
	page = pg
	for k in pages.keys():
		pages[k].visible = k == pg
	for k in nav_btns.keys():
		nav_btns[k].modulate = Color(1.0, 0.85, 0.4) if k == pg else Color(1, 1, 1, 0.85)
	match pg:
		"home":
			_refresh_menu_meta()
		"profile":
			_fill_profile()
		"fleet":
			_fill_menu_cards(menu_tier)
		"progress":
			_fill_progress()
		"configs":
			_sync_settings()
	if not silent:
		audio_click()

# ---------------- HOME ----------------

func _page_home() -> Control:
	var pg := Control.new()
	pg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_box.add_child(pg)
	_rect(pg, 0, 0, 0, 0, 0, 0, 0, 0)
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pg.add_child(cc)
	_rect(cc, 0, 0, 0, 0, 0, 0, 0, 0)
	var card := _panel(cc, Color(0.03, 0.09, 0.16, 0.92), 30.0, 16)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	card.add_child(v)
	var big_logo := Control.new()
	big_logo.custom_minimum_size = Vector2(300, 140)
	big_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	big_logo.draw.connect(_draw_big_logo.bind(big_logo))
	v.add_child(big_logo)
	var t := _label(v, "TOTAL WAR ON THE HIGH SEAS", 20, Color(0.86, 0.69, 0.22))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var note := _label(v, "Every battle starts at Tier I. Sink ships, collect supplies, promote in battle through ten tiers.", 14, TEXT_DIM)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(560, 0)
	play_btn = _make_button(v, "Loading world...  0%", 28, Vector2(620, 74))
	play_btn.disabled = true
	play_btn.pressed.connect(_on_play_clicked)
	ranked_btn = _make_button(v, "RANKED: OFF", 16, Vector2(620, 46), Color(0.3, 0.34, 0.4))
	ranked_btn.pressed.connect(_toggle_ranked)
	var net_row := HBoxContainer.new()
	net_row.alignment = BoxContainer.ALIGNMENT_CENTER
	net_row.add_theme_constant_override("separation", 10)
	v.add_child(net_row)
	var host_btn := _make_button(net_row, "HOST ONLINE MATCH", 16, Vector2(300, 42), Color(0.16, 0.40, 0.30))
	host_btn.pressed.connect(func():
		audio_click()
		host_requested.emit())
	var join_btn := _make_button(net_row, "JOIN MATCH", 16, Vector2(300, 42), Color(0.45, 0.33, 0.12))
	join_btn.pressed.connect(func():
		audio_click()
		_open_join())
	var addr_row := HBoxContainer.new()
	addr_row.alignment = BoxContainer.ALIGNMENT_CENTER
	addr_row.add_theme_constant_override("separation", 8)
	v.add_child(addr_row)
	host_addr_lbl = _label(addr_row, "", 13, Color(0.6, 1.0, 0.85))
	var copyb := _make_button(addr_row, "COPY", 12, Vector2(70, 30), Color(0.2, 0.3, 0.45))
	copyb.pressed.connect(func():
		audio_click()
		DisplayServer.clipboard_set(host_addr_lbl.text)
		toast("Address copied - send it to your friend"))
	profile_lbl = _label(v, "", 14, TEXT)
	profile_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rank_lbl = _label(v, "", 15, WARN)
	rank_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	meta_bar = _bar(v, 8.0, ACCENT_HI)
	return pg

# ---------------- PROFILE ----------------

func _page_profile() -> Control:
	var pg := Control.new()
	pg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_box.add_child(pg)
	_rect(pg, 0, 0, 0, 0, 0, 0, 0, 0)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pg.add_child(sc)
	_rect(sc, 0, 0, 0, 0, 0, 0, 0, 0)
	var cc := CenterContainer.new()
	sc.add_child(cc)
	cc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var card := _panel(cc, PANEL_BG, 26.0, 14)
	card.custom_minimum_size = Vector2(880, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	card.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 24)
	v.add_child(top)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	top.add_child(left)
	var t1 := _label(left, "RANK INSIGNIA", 16, Color(0.86, 0.69, 0.22))
	t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge_ctl = Control.new()
	badge_ctl.custom_minimum_size = Vector2(170, 170)
	badge_ctl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge_ctl.draw.connect(_draw_profile_badge.bind(badge_ctl))
	badge_ctl.pivot_offset = Vector2(85, 85)
	left.add_child(badge_ctl)
	var rank_big := _label(left, "", 18, WARN)
	rank_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prof_d["rank_big"] = rank_big
	var rp_lbl := _label(left, "", 13, TEXT_DIM)
	rp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prof_d["rp_lbl"] = rp_lbl
	var season_lbl := _label(left, "", 12, Color(0.6, 1.0, 0.85))
	season_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prof_d["season_lbl"] = season_lbl
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(right)
	var t2 := _label(right, "CAPTAIN'S LOG", 16, ACCENT_HI)
	var nrow := HBoxContainer.new()
	nrow.add_theme_constant_override("separation", 10)
	right.add_child(nrow)
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Nickname"
	name_edit.max_length = 14
	name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_edit.custom_minimum_size = Vector2(240, 40)
	name_edit.add_theme_font_size_override("font_size", 18)
	var ne := StyleBoxFlat.new()
	ne.bg_color = Color(0, 0, 0, 0.35)
	ne.set_corner_radius_all(10)
	ne.set_content_margin_all(8)
	ne.border_color = Color(1, 1, 1, 0.15)
	ne.set_border_width_all(1)
	var nf := ne.duplicate() as StyleBoxFlat
	nf.border_color = ACCENT_HI
	nf.set_border_width_all(2)
	name_edit.add_theme_stylebox_override("normal", ne)
	name_edit.add_theme_stylebox_override("focus", nf)
	name_edit.add_theme_color_override("font_color", Color.WHITE)
	name_edit.add_theme_color_override("font_placeholder_color", Color(1, 1, 1, 0.4))
	nrow.add_child(name_edit)
	name_edit.text_submitted.connect(func(_t: String): _apply_nick())
	var applyb := _make_button(nrow, "APPLY", 14, Vector2(100, 40), Color(0.16, 0.36, 0.5))
	applyb.pressed.connect(_apply_nick)
	var msg := _label(right, "", 12, Color(1.0, 0.5, 0.45))
	prof_d["msg"] = msg
	var lvl_lbl := _label(right, "", 14, TEXT)
	prof_d["lvl_lbl"] = lvl_lbl
	var xp_bar := _bar(right, 10.0, ACCENT_HI)
	prof_d["xp_bar"] = xp_bar
	meta_bar = xp_bar
	var stat_lbl := _label(right, "", 13, TEXT_DIM)
	stat_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prof_d["stat_lbl"] = stat_lbl
	var pt := _label(right, "HULL PAINT  (unlocked in the Battle Pass)", 13, Color(0.86, 0.69, 0.22))
	paint_row = HBoxContainer.new()
	paint_row.add_theme_constant_override("separation", 8)
	right.add_child(paint_row)
	var outrow := HBoxContainer.new()
	outrow.add_theme_constant_override("separation", 10)
	right.add_child(outrow)
	var logout := _make_button(outrow, "LOG OUT", 14, Vector2(140, 38), Color(0.5, 0.25, 0.22))
	logout.pressed.connect(_logout)
	return pg

func _apply_nick() -> void:
	var n := str(name_edit.text).strip_edges()
	if n.is_empty():
		return
	if not _nick_strict(n):
		if prof_d.has("msg"):
			(prof_d["msg"] as Label).text = "That nickname is not allowed."
		return
	S.d["nick"] = n
	S.save_file()
	if prof_d.has("msg"):
		(prof_d["msg"] as Label).text = "Nickname saved."
	_fill_profile()

func _logout() -> void:
	S.logout()
	guest_mode = false
	_goto("home", true)
	show_menu()

func _fill_profile() -> void:
	if prof_d.is_empty():
		return
	var xp := int(S.d.get("xp", 0))
	var meta := D.level_progress(xp)
	var ri := D.rank_i_from_rp(int(S.d.get("rp", 0)))
	prof_ri = ri
	badge_ctl.queue_redraw()
	(prof_d["rank_big"] as Label).text = str(D.RANKS[ri][1]).to_upper()
	(prof_d["rp_lbl"] as Label).text = "%d Ranked Rating" % int(S.d.get("rp", 0))
	(prof_d["season_lbl"] as Label).text = "Season %d ends in %d days" % [int(S.d.get("season", 1)), S.season_days_left()]
	(prof_d["msg"] as Label).text = ""
	name_edit.text = str(S.d.get("nick", "Captain"))
	(prof_d["lvl_lbl"] as Label).text = "Level %d  -  %d / %d XP" % [int(meta["lvl"]), int(meta["have"]), int(meta["need"])]
	(prof_d["xp_bar"] as ProgressBar).value = clampf(float(meta["have"]) / float(maxi(int(meta["need"]), 1)), 0.0, 1.0)
	(prof_d["stat_lbl"] as Label).text = "Battles fought: %d      Ships sunk: %d      Best score: %d" % [int(S.d.get("battles", 0)), int(S.d.get("kills", 0)), int(S.d.get("best", 0))]
	paint_unlocks()

func paint_unlocked(pk: String) -> bool:
	if pk == "navy":
		return true
	var claimed := int(S.d.get("bp_claim", 0))
	for i in D.BP_REWARDS.size():
		var rw: Dictionary = D.BP_REWARDS[i]
		if str(rw["k"]) == "paint" and str(rw["v"]) == pk:
			return (claimed >> i) & 1 == 1
	return false

func paint_unlocks() -> void:
	if paint_row == null:
		return
	_clear(paint_row)
	var cur := str(S.d.get("paint", "navy"))
	for pk in D.PAINTS.keys():
		var b := Button.new()
		b.custom_minimum_size = Vector2(52, 52)
		b.focus_mode = Control.FOCUS_NONE
		var sb := StyleBoxFlat.new()
		if paint_unlocked(str(pk)):
			sb.bg_color = D.PAINTS[pk]["c"]
			b.tooltip_text = str(D.PAINTS[pk]["n"])
		else:
			sb.bg_color = Color(0.1, 0.1, 0.12)
			b.tooltip_text = "%s  (locked - Battle Pass)" % str(D.PAINTS[pk]["n"])
		sb.set_corner_radius_all(10)
		sb.border_color = Color(0.86, 0.69, 0.22) if pk == cur else Color(1, 1, 1, 0.18)
		sb.set_border_width_all(3 if pk == cur else 1)
		b.add_theme_stylebox_override("normal", sb)
		b.pressed.connect(_pick_paint.bind(str(pk)))
		paint_row.add_child(b)

func _pick_paint(pk: String) -> void:
	if not paint_unlocked(pk):
		toast("Unlock that paint in the Battle Pass (Progress page).")
		return
	S.d["paint"] = pk
	S.save_file()
	audio_click()
	paint_unlocks()

# ---------------- FLEET BROWSER ----------------

func _page_fleet() -> Control:
	var pg := Control.new()
	pg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_box.add_child(pg)
	_rect(pg, 0, 0, 0, 0, 0, 0, 0, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pg.add_child(v)
	_rect(v, 0, 0, 0, 0, 0, 0, 0, 0)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	v.add_child(head)
	var t := _label(head, "THE FLEET", 30, Color.WHITE)
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var cls_lbl := _label(head, "Every class, every tier. Ships you have commanded are lit up; click any hull for its full profile.", 14, TEXT_DIM)
	cls_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var back := _make_button(head, "BACK TO PORT", 15, Vector2(170, 44), Color(0.3, 0.34, 0.4))
	back.pressed.connect(_goto.bind("home"))
	var tiers := HBoxContainer.new()
	tiers.add_theme_constant_override("separation", 6)
	tiers.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(tiers)
	_label(tiers, "TIER", 13, TEXT_DIM)
	tier_row = HBoxContainer.new()
	tier_row.add_theme_constant_override("separation", 6)
	tier_row.alignment = BoxContainer.ALIGNMENT_CENTER
	tiers.add_child(tier_row)
	for tt in D.MAX_TIER:
		_make_button(tier_row, str(D.ROMAN[tt]), 17, Vector2(58, 40), Color(0.25, 0.29, 0.36)).pressed.connect(_sel_tier.bind(tt + 1))
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 14)
	v.add_child(split)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(sc)
	fleet_grid = GridContainer.new()
	fleet_grid.columns = 4
	fleet_grid.add_theme_constant_override("h_separation", 12)
	fleet_grid.add_theme_constant_override("v_separation", 12)
	fleet_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(fleet_grid)
	var det := _panel(split, Color(0.04, 0.10, 0.18, 0.95), 14.0, 12)
	det.custom_minimum_size = Vector2(360, 0)
	det.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fleet_detail = VBoxContainer.new()
	fleet_detail.add_theme_constant_override("separation", 8)
	det.add_child(fleet_detail)
	var dv := _label(fleet_detail, "Select a hull to open its full profile - every stat fits on this page, even for ships you have never played.", 12, TEXT_DIM)
	dv.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return pg

func _fleet_pick(id: String) -> void:
	fleet_did = id
	var def := D.by_id(id)
	if def.is_empty() or fleet_detail == null:
		return
	_clear(fleet_detail)
	var lvl := D.level_from_xp(int(S.d.get("xp", 0)))
	var locked := not D.unlocked(def, lvl)
	var played := S.has_played(str(def["id"]))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	fleet_detail.add_child(head)
	var ic := Control.new()
	ic.custom_minimum_size = Vector2(96, 56)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.draw.connect(_draw_preview.bind(ic, def))
	head.add_child(ic)
	var hv := VBoxContainer.new()
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hv)
	_label(hv, str(def["name"]), 16, Color.WHITE)
	_label(hv, "Tier %s  |  %s  |  %dm x %dm" % [str(D.ROMAN[int(def["tier"]) - 1]), str(def["cls"]), int(def["len"]), int(def["wid"])], 11, ACCENT_HI)
	var status := "FLOWN BY YOU" if played else ("LOCKED - LEVEL %d" % int(def.get("lvl", 1)) if locked else "NEVER COMMANDED")
	_label(fleet_detail, status, 12, GOOD if played else (BAD if locked else TEXT_DIM))
	var dsc := _label(fleet_detail, str(def.get("desc", "")), 12, TEXT)
	dsc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dsc.custom_minimum_size = Vector2(320, 0)
	fleet_detail.add_child(_label(fleet_detail, "HULL", 10, TEXT_DIM))
	_stat_row(fleet_detail, "%d HP" % int(def["hp"]), clampf(float(def["hp"]) / 20000.0, 0.02, 1.0), GOOD)
	fleet_detail.add_child(_label(fleet_detail, "TOP SPEED", 10, TEXT_DIM))
	_stat_row(fleet_detail, "%d kn" % int(def["spd"]), clampf(float(def["spd"]) / 250.0, 0.02, 1.0), ACCENT)
	fleet_detail.add_child(_label(fleet_detail, "FIREPOWER", 10, TEXT_DIM))
	_stat_row(fleet_detail, "%d dps" % int(D.dps(def)), clampf(D.dps(def) / 2200.0, 0.02, 1.0), BAD)
	fleet_detail.add_child(_label(fleet_detail, "SPOT RANGE", 10, TEXT_DIM))
	_stat_row(fleet_detail, "%dm" % int(def["det"]), clampf(float(def["det"]) / 2300.0, 0.02, 1.0), WARN)
	var fld := _label(fleet_detail, _weapon_lines(def, 10), 11, TEXT)
	fld.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fld.custom_minimum_size = Vector2(320, 0)
	var abil: Array = []
	for a in def["abil"]:
		abil.append(str(D.ABILITIES[str(a)]["n"]))
	var al := _label(fleet_detail, "Abilities: " + ", ".join(abil), 11, TEXT_DIM)
	al.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	al.custom_minimum_size = Vector2(320, 0)
	if str(def["air"]) != "":
		var sqn := int(def.get("squad", 1))
		var air2 := str(def.get("air2", ""))
		var atxt := "Aircraft: %s (squad of %d)" % [str(D.AIR[str(def["air"])]["n"]), sqn]
		if air2 != "":
			atxt += "   +   %s wingmen" % str(D.AIR[air2]["n"])
		var ail := _label(fleet_detail, atxt, 11, Color(0.6, 0.95, 1.0))
		ail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ail.custom_minimum_size = Vector2(320, 0)
	if str(def["cls"]) == "Submarine":
		var sl := _label(fleet_detail, "Emergency Dive: guns cannot touch you while dived - only torpedoes. Dive has no cooldown.", 11, Color(0.6, 1.0, 0.85))
		sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sl.custom_minimum_size = Vector2(320, 0)

# ---------------- PROGRESS: ranks + battle pass + missions ----------------

func _page_progress() -> Control:
	var pg := Control.new()
	pg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_box.add_child(pg)
	_rect(pg, 0, 0, 0, 0, 0, 0, 0, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pg.add_child(v)
	_rect(v, 0, 0, 0, 0, 0, 0, 0, 0)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := _label(head, "BATTLE PASS  &  RANKED LADDER", 30, Color.WHITE)
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var back := _make_button(head, "BACK TO PORT", 15, Vector2(170, 44), Color(0.3, 0.34, 0.4))
	back.pressed.connect(_goto.bind("home"))
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 14)
	v.add_child(split)
	var lp := _panel(split, PANEL_BG, 14.0, 12)
	lp.custom_minimum_size = Vector2(300, 0)
	lp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 2)
	lp.add_child(lv)
	_label(lv, "RANKED LADDER", 16, Color(0.86, 0.69, 0.22))
	rank_box = VBoxContainer.new()
	rank_box.add_theme_constant_override("separation", 2)
	lv.add_child(rank_box)
	var rp := _panel(split, PANEL_BG, 14.0, 12)
	rp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 10)
	rp.add_child(rv)
	_label(rv, "DAILY MISSIONS  (BP points on completion)", 16, ACCENT_HI)
	mission_box = VBoxContainer.new()
	mission_box.add_theme_constant_override("separation", 6)
	rv.add_child(mission_box)
	_label(rv, "BATTLE PASS SEASON  -  20 TIERS", 16, ACCENT_HI)
	var bphint := _label(rv, "Play battles and complete missions to earn Battle Pass points. Rewards reset every 20 days with your rank.", 12, TEXT_DIM)
	bphint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var bpsc := ScrollContainer.new()
	bpsc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bpsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rv.add_child(bpsc)
	bp_grid = GridContainer.new()
	bp_grid.columns = 5
	bp_grid.add_theme_constant_override("h_separation", 10)
	bp_grid.add_theme_constant_override("v_separation", 10)
	bp_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bpsc.add_child(bp_grid)
	return pg

func _badge_node(parent: Node, ri: int, r: float) -> Control:
	var badge := Control.new()
	badge.custom_minimum_size = Vector2(r * 2.7, r * 2.3)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.draw.connect(_draw_rank_badge.bind(badge, ri, r))
	parent.add_child(badge)
	return badge

func _fill_progress() -> void:
	var my_ri := D.rank_i_from_rp(int(S.d.get("rp", 0)))
	if rank_box != null:
		_clear(rank_box)
		for i in D.RANKS.size():
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			rank_box.add_child(row)
			_badge_node(row, i, 13.0)
			var nm := _label(row, "%s" % str(D.RANKS[i][1]), 13, Color(1.0, 0.85, 0.4) if i == my_ri else TEXT)
			nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_label(row, "%d RP" % int(D.RANKS[i][0]), 11, TEXT_DIM)
	if mission_box != null:
		_clear(mission_box)
		if game == null:
			mission_box.add_child(_label(mission_box, "Missions unlock in battle.", 12, TEXT_DIM))
		else:
			for m in game.get_missions():
				var row2 := HBoxContainer.new()
				row2.add_theme_constant_override("separation", 10)
				mission_box.add_child(row2)
				var txt := "%s   (%d / %d)" % [str(m["n"]), int(m["have"]), int(m["need"])]
				var ml := _label(row2, txt, 13, TEXT)
				ml.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				var cb := _make_button(row2, ("CLAIMED" if bool(m["claimed"]) else ("CLAIM +%d BP" % int(m["reward"]))), 12, Vector2(140, 30), Color(0.36, 0.25, 0.1))
				var can := bool(m["done"]) and not bool(m["claimed"])
				cb.disabled = not can
				cb.modulate = Color(1, 1, 1, 1.0) if can else Color(1, 1, 1, 0.45)
				cb.pressed.connect(_claim_mission.bind(int(m["slot_bit"]), int(m["reward"]), str(m["n"])))
	if bp_grid != null:
		_clear(bp_grid)
		var bpn := int(S.d.get("bp", 0))
		var claimed := int(S.d.get("bp_claim", 0))
		for i in D.BP_REWARDS.size():
			var cost := D.BP_TIER_COST * (i + 1)
			var rw: Dictionary = D.BP_REWARDS[i]
			var has := (claimed >> i) & 1 == 1
			var reach := bpn >= cost
			var card := _panel(bp_grid, Color(0.05, 0.12, 0.2, 0.95), 8.0, 8)
			card.custom_minimum_size = Vector2(150, 0)
			var cv := VBoxContainer.new()
			card.add_child(cv)
			_label(cv, "TIER %d" % (i + 1), 11, TEXT_DIM)
			var rl := _label(cv, str(rw["n"]), 11, WARN)
			rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			rl.custom_minimum_size = Vector2(134, 0)
			var btn := _make_button(cv, ("CLAIMED" if has else ("CLAIM  (%d BP)" % cost if reach else "%d / %d BP" % [bpn, cost])), 11, Vector2(0, 26), Color(0.36, 0.25, 0.1))
			btn.disabled = has or not reach
			btn.modulate = Color(1, 1, 1, 1.0) if (reach and not has) else Color(1, 1, 1, 0.5)
			btn.pressed.connect(_claim_bp.bind(i, str(rw["n"])))

func _claim_mission(slot_bit: int, reward: int, mname: String) -> void:
	if game == null:
		return
	game.claim_mission(slot_bit, reward)
	toast("Mission complete: %s  +%d BP" % [mname, reward])
	_fill_progress()

func _claim_bp(idx: int, rname: String) -> void:
	var claimed := int(S.d.get("bp_claim", 0))
	if (claimed >> idx) & 1 == 1:
		return
	var cost := D.BP_TIER_COST * (idx + 1)
	var bpn := int(S.d.get("bp", 0))
	if bpn < cost:
		toast("Need %d Battle Pass points." % cost)
		return
	bpn -= cost
	S.d["bp"] = bpn
	S.d["bp_claim"] = claimed | (1 << idx)
	var rw: Dictionary = D.BP_REWARDS[idx]
	match str(rw["k"]):
		"xp":
			S.d["xp"] = int(S.d.get("xp", 0)) + int(rw["v"])
		"rp":
			S.d["rp"] = int(S.d.get("rp", 0)) + int(rw["v"])
	S.save_file()
	toast("Battle Pass: %s" % rname)
	_fill_progress()
	_fill_profile()

# ---------------- rank badge / logo drawing ----------------

func _draw_profile_badge(c: Control) -> void:
	_draw_rank_badge(c, prof_ri, 55.0)

func _rank_polygon(sh: int, r: float, ctr: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	match sh:
		1:
			pts.append(ctr + Vector2(0, -r))
			pts.append(ctr + Vector2(r * 0.85, -r * 0.55))
			pts.append(ctr + Vector2(r * 0.72, r * 0.42))
			pts.append(ctr + Vector2(0, r))
			pts.append(ctr + Vector2(-r * 0.72, r * 0.42))
			pts.append(ctr + Vector2(-r * 0.85, -r * 0.55))
		2:
			for i in 6:
				pts.append(ctr + Vector2.from_angle(TAU * i / 6.0 - PI / 2.0) * r)
		3:
			for i in 10:
				var rr := r if i % 2 == 0 else r * 0.45
				pts.append(ctr + Vector2.from_angle(TAU * i / 10.0 - PI / 2.0) * rr)
		4:
			pts.append(ctr + Vector2(-r, r * 0.55))
			pts.append(ctr + Vector2(-r, -r * 0.15))
			pts.append(ctr + Vector2(-r * 0.5, r * 0.18))
			pts.append(ctr + Vector2(0, -r))
			pts.append(ctr + Vector2(r * 0.5, r * 0.18))
			pts.append(ctr + Vector2(r, -r * 0.15))
			pts.append(ctr + Vector2(r, r * 0.55))
	return pts

func _draw_rank_badge(c: Control, ri: int, r: float) -> void:
	if ri < 0 or ri >= D.RANK_META.size():
		return
	var m: Dictionary = D.RANK_META[ri]
	var col: Color = m["col"]
	var dark := col.darkened(0.55)
	var ctr := c.size * 0.5
	if c.size.x < 2.0:
		ctr = c.custom_minimum_size * 0.5
	match int(m["sh"]):
		0:
			c.draw_arc(ctr, r * 0.95, 0, TAU, 32, col, r * 0.16, true)
			c.draw_circle(ctr, r * 0.42, col)
		5:
			c.draw_circle(ctr, r, Color(0.03, 0.09, 0.05, 0.9))
			c.draw_arc(ctr, r, 0, TAU, 40, dark, r * 0.12, true)
			for k in 3:
				var ca := -PI / 2.0 + TAU * k / 3.0
				var w := PackedVector2Array()
				w.append(ctr + Vector2.from_angle(ca - 0.28) * r * 0.32)
				for i in 5:
					w.append(ctr + Vector2.from_angle(ca - 0.28 + 0.56 * i / 4.0) * r * 0.88)
				w.append(ctr + Vector2.from_angle(ca + 0.28) * r * 0.32)
				c.draw_colored_polygon(w, col)
			c.draw_circle(ctr, r * 0.16, Color(0.03, 0.09, 0.05, 1.0))
		_:
			var pts := _rank_polygon(int(m["sh"]), r * 0.92, ctr)
			if pts.size() >= 3:
				c.draw_colored_polygon(pts, dark)
				var outline := pts.duplicate()
				outline.append(pts[0])
				c.draw_polyline(outline, col, r * 0.13, true)
	var pips := int(m["pips"])
	for i in pips:
		c.draw_circle(Vector2(ctr.x + (float(i) - float(pips - 1) * 0.5) * r * 0.52, ctr.y + r * 1.24), r * 0.14, col)

func _draw_logo(c: Control, s: float) -> void:
	var r := 26.0 * s
	var ctr := Vector2(r * 1.2, r * 1.2)
	var gold := Color(0.86, 0.69, 0.22)
	var white := Color(0.95, 0.97, 1.0, 0.95)
	c.draw_circle(ctr, r, Color(0.05, 0.12, 0.2, 0.95))
	c.draw_arc(ctr, r, 0, TAU, 40, gold, 3.5 * s, true)
	c.draw_arc(ctr + Vector2(0, -r * 0.62), r * 0.2, 0, TAU, 16, white, 2.2 * s, true)
	c.draw_line(ctr + Vector2(0, -r * 0.42), ctr + Vector2(0, r * 0.55), white, 2.6 * s, true)
	c.draw_line(ctr + Vector2(-r * 0.34, -r * 0.16), ctr + Vector2(r * 0.34, -r * 0.16), white, 2.6 * s, true)
	c.draw_arc(ctr + Vector2(0, -r * 0.05), r * 0.5, PI * 0.12, PI * 0.88, 24, white, 2.6 * s, true)

func _draw_big_logo(c: Control) -> void:
	var gold := Color(0.86, 0.69, 0.22)
	_draw_logo(c, 1.0)
	var wp := c.get_theme_default_font()
	if wp == null:
		return
	c.draw_string(wp, Vector2(78, 66), "NAVAL", HORIZONTAL_ALIGNMENT_LEFT, -1, 52, Color.WHITE)
	c.draw_string(wp, Vector2(288, 66), ".IO", HORIZONTAL_ALIGNMENT_LEFT, -1, 52, gold)
	c.draw_string(wp, Vector2(80, 92), "CARRIER VS BATTLESHIP  -  TEN TIERS OF STEEL", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.75))

# ---------------- LOGIN ----------------

func _build_login() -> void:
	login_root = Control.new()
	root.add_child(login_root)
	login_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.008, 0.025, 0.055, 1.0)
	login_root.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var cc := CenterContainer.new()
	login_root.add_child(cc)
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var card := _panel(cc, Color(0.03, 0.08, 0.15, 0.99), 28.0, 16)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	card.add_child(v)
	var big_logo := Control.new()
	big_logo.custom_minimum_size = Vector2(320, 80)
	big_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	big_logo.draw.connect(_draw_big_logo.bind(big_logo))
	v.add_child(big_logo)
	_label(v, "WELCOME ABOARD, CAPTAIN", 18, Color(0.86, 0.69, 0.22)).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var note := _label(v, "CREATE ACCOUNT the first time (pick a name + password). Same password and name = same fleet, level, rank and battle pass on every device and download.", 13, TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(420, 0)
	login_nick = LineEdit.new()
	login_nick.placeholder_text = "Nickname  (only needed when creating an account)"
	login_nick.max_length = 14
	login_nick.custom_minimum_size = Vector2(0, 44)
	login_nick.alignment = HORIZONTAL_ALIGNMENT_CENTER
	login_nick.add_theme_font_size_override("font_size", 16)
	var lne := StyleBoxFlat.new()
	lne.bg_color = Color(0, 0, 0, 0.4)
	lne.set_corner_radius_all(10)
	lne.set_content_margin_all(8)
	lne.border_color = Color(1, 1, 1, 0.15)
	lne.set_border_width_all(1)
	var lnf := lne.duplicate() as StyleBoxFlat
	lnf.border_color = Color(0.30, 0.65, 1.0)
	lnf.set_border_width_all(2)
	login_nick.add_theme_stylebox_override("normal", lne)
	login_nick.add_theme_stylebox_override("focus", lnf)
	login_nick.add_theme_color_override("font_color", Color.WHITE)
	login_nick.add_theme_color_override("font_placeholder_color", Color(1, 1, 1, 0.4))
	v.add_child(login_nick)
	login_pin = LineEdit.new()
	login_pin.secret = true
	login_pin.secret_character = "x"
	login_pin.placeholder_text = "Password"
	login_pin.custom_minimum_size = Vector2(0, 46)
	login_pin.alignment = HORIZONTAL_ALIGNMENT_CENTER
	login_pin.add_theme_font_size_override("font_size", 18)
	var ne := StyleBoxFlat.new()
	ne.bg_color = Color(0, 0, 0, 0.4)
	ne.set_corner_radius_all(10)
	ne.set_content_margin_all(8)
	ne.border_color = Color(1, 1, 1, 0.15)
	ne.set_border_width_all(1)
	var nf := ne.duplicate() as StyleBoxFlat
	nf.border_color = Color(0.86, 0.69, 0.22)
	nf.set_border_width_all(2)
	login_pin.add_theme_stylebox_override("normal", ne)
	login_pin.add_theme_stylebox_override("focus", nf)
	login_pin.add_theme_color_override("font_color", Color.WHITE)
	v.add_child(login_pin)
	login_pin.text_submitted.connect(func(_t: String): _login_confirm())
	login_err = _label(v, "", 12, Color(1.0, 0.5, 0.45))
	login_err.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	var mk := _make_button(row, "CREATE ACCOUNT", 15, Vector2(0, 50), Color(0.10, 0.44, 0.30))
	mk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mk.pressed.connect(_create_confirm)
	var go := _make_button(row, "LOG IN", 15, Vector2(120, 50))
	go.pressed.connect(_login_confirm)
	var guest := _make_button(row, "GUEST", 14, Vector2(90, 50), Color(0.3, 0.34, 0.4))
	guest.pressed.connect(_login_guest)
	var hint2 := _label(v, "Passwords are case sensitive. Forgetting it means a new empty fleet - there is no recovery, this game has no servers.", 11, TEXT_DIM)
	hint2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint2.custom_minimum_size = Vector2(420, 0)

func _build_join() -> void:
	join_root = Control.new()
	root.add_child(join_root)
	join_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	join_root.visible = false
	var bg := ColorRect.new()
	bg.color = Color(0.008, 0.025, 0.055, 0.94)
	join_root.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var cc := CenterContainer.new()
	join_root.add_child(cc)
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var card := _panel(cc, Color(0.03, 0.08, 0.15, 0.99), 28.0, 16)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	card.add_child(v)
	_label(v, "JOIN A FRIEND'S BATTLE", 20, Color(0.86, 0.69, 0.22)).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var note := _label(v, "The host presses HOST ONLINE MATCH and a public internet address appears on their screen. Type that address here - both must run the same version of the game.", 13, TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(460, 0)
	join_ip_edit = LineEdit.new()
	join_ip_edit.placeholder_text = "host address (like 84.123.x.x or 192.168.1.20)"
	join_ip_edit.custom_minimum_size = Vector2(0, 46)
	join_ip_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	join_ip_edit.add_theme_font_size_override("font_size", 16)
	var je := StyleBoxFlat.new()
	je.bg_color = Color(0, 0, 0, 0.4)
	je.set_corner_radius_all(10)
	je.set_content_margin_all(8)
	je.border_color = Color(1, 1, 1, 0.15)
	je.set_border_width_all(1)
	var jf := je.duplicate() as StyleBoxFlat
	jf.border_color = Color(0.86, 0.69, 0.22)
	jf.set_border_width_all(2)
	join_ip_edit.add_theme_stylebox_override("normal", je)
	join_ip_edit.add_theme_stylebox_override("focus", jf)
	join_ip_edit.add_theme_color_override("font_color", Color.WHITE)
	v.add_child(join_ip_edit)
	join_ip_edit.text_submitted.connect(func(_t: String): _join_confirm())
	join_err = _label(v, "", 12, Color(1.0, 0.5, 0.45))
	join_err.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	var go := _make_button(row, "JOIN BATTLE", 18, Vector2(0, 50), Color(0.45, 0.33, 0.12))
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go.pressed.connect(_join_confirm)
	var cancel := _make_button(row, "CANCEL", 14, Vector2(110, 50), Color(0.3, 0.34, 0.4))
	cancel.pressed.connect(_join_cancel)
	var mlbl := _label(v, "MATCHES FOUND ON THIS NETWORK", 13, Color(0.86, 0.69, 0.22))
	v.add_child(mlbl)
	match_msg = _label(v, "Searching for nearby matches...", 12, TEXT_DIM)
	v.add_child(match_msg)
	match_list = VBoxContainer.new()
	match_list.add_theme_constant_override("separation", 6)
	v.add_child(match_list)
	var hint := _label(v, "Strangers on the same wifi appear here automatically. Someone on another internet connection? The host Copies their address (shown after hosting) and sends it to you - the game has no master server, so across the internet the address is how you find each other.", 11, TEXT_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(460, 0)

func _open_join() -> void:
	if join_root == null:
		return
	join_ip_edit.text = ""
	join_err.text = ""
	match_msg.text = "Searching for nearby matches..."
	for r in match_rows:
		(r as Control).queue_free()
	match_rows.clear()
	join_root.visible = true

func set_host_addr(addr: String) -> void:
	if host_addr_lbl != null:
		host_addr_lbl.text = addr

func set_matches(ms: Array) -> void:
	if match_list == null or not join_root.visible:
		return
	for r in match_rows:
		(r as Control).queue_free()
	match_rows.clear()
	if ms.is_empty():
		match_msg.text = "No matches on this network yet - keep this open while the host starts one."
		return
	match_msg.text = "%d match(es) found - click to join:" % ms.size()
	for m in ms:
		var txt := "%s  -  %s" % [str(m[1]), str(m[0])]
		var b := _make_button(match_list, txt, 13, Vector2(460, 34), Color(0.16, 0.40, 0.30))
		b.pressed.connect(func():
			audio_click()
			join_ip_edit.text = str(m[0])
			_join_confirm())
		match_rows.append(b)

func _join_cancel() -> void:
	if join_root != null:
		join_root.visible = false
	audio_click()

func _join_confirm() -> void:
	if join_root == null:
		return
	var ip := join_ip_edit.text.strip_edges()
	if ip.is_empty():
		join_err.text = "Type the host's address first."
		return
	join_root.visible = false
	join_requested.emit(ip)

func _nick_strict(n: String) -> bool:
	if not D.nick_ok(n):
		return false
	for bad in ["<", ">", "&", "/", "\\", "{", "}"]:
		if n.contains(bad):
			return false
	return true

func _create_confirm() -> void:
	var nick := login_nick.text.strip_edges()
	var pin := login_pin.text.strip_edges()
	if nick.is_empty():
		login_err.text = "Pick a nickname first."
		return
	if not _nick_strict(nick) or nick.length() < 3:
		login_err.text = "That nickname is not allowed (3-14 letters, nothing rude)."
		return
	if pin.length() < 4:
		login_err.text = "Password needs at least 4 characters."
		return
	var r := S.create_account(pin, nick)
	if r == 1:
		login_err.text = "That password is already used. Use LOG IN."
		return
	if r != 0:
		login_err.text = "Could not create the account. Try again."
		return
	_after_login(nick)

func _login_confirm() -> void:
	var pin := login_pin.text.strip_edges()
	if pin.is_empty():
		login_err.text = "Type a password first."
		return
	if S.load_account(pin):
		_after_login(str(S.d.get("nick", "Captain")))
	else:
		login_err.text = "No account with that password. Create one first." if S.login_missing else "Login failed."

func _after_login(nname: String) -> void:
	login_root.visible = false
	guest_mode = false
	name_edit.text = str(S.d.get("nick", "Captain"))
	_refresh_menu_meta()
	_fill_progress()
	_fill_profile()
	toast("Welcome to the fleet, %s" % nname)

func _login_guest() -> void:
	guest_mode = true
	login_root.visible = false
	audio_click()

# ---------------- BATTLE RESULTS (exit progress) ----------------

func _build_results() -> void:
	results_root = Control.new()
	root.add_child(results_root)
	results_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.008, 0.025, 0.055, 0.9)
	results_root.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var cc := CenterContainer.new()
	results_root.add_child(cc)
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var card := _panel(cc, Color(0.03, 0.08, 0.15, 0.99), 26.0, 16)
	card.custom_minimum_size = Vector2(620, 0)
	res_box = VBoxContainer.new()
	res_box.add_theme_constant_override("separation", 12)
	card.add_child(res_box)

func show_battle_results(res: Dictionary) -> void:
	menu_root.visible = true
	_refresh_menu_meta()
	if results_root == null:
		return
	results_root.visible = true
	res_ri = int(res.get("ri1", 0))
	_clear(res_box)
	var t := _label(res_box, "BATTLE REPORT", 30, Color.WHITE)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var mins := int(res.get("time", 0)) / 60
	var secs := int(res.get("time", 0)) % 60
	_label(res_box, "%d:%02d at sea  -  %d ships sunk  -  %d damage  -  %d score" % [mins, secs, int(res.get("kills", 0)), int(res.get("dmg", 0)), int(res.get("score", 0))], 14, TEXT).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label(res_box, "EXPERIENCE", 13, ACCENT_HI)
	var xp_res := _bar(res_box, 12.0, ACCENT_HI)
	var lvl_gain := int(res.get("lvl1", 0)) - int(res.get("lvl0", 0))
	var lvl_txt := "LEVEL %d" % int(res.get("lvl1", 0))
	if lvl_gain > 0:
		lvl_txt = "LEVEL UP!  NOW LEVEL %d" % int(res.get("lvl1", 0))
	var lvl_lbl := _label(res_box, lvl_txt + ("   +%d XP" % (int(res.get("xp1", 0)) - int(res.get("xp0", 0)))), 16, GOOD if lvl_gain > 0 else TEXT)
	lvl_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lvl_lbl.pivot_offset = Vector2(280, 14)
	if int(res.get("ranked", 0)):
		_label(res_box, "RANKED RATING", 13, WARN)
		var rank_row := HBoxContainer.new()
		rank_row.add_theme_constant_override("separation", 14)
		res_box.add_child(rank_row)
		_badge_node(rank_row, int(res.get("ri1", 0)), 26.0)
		var rv := VBoxContainer.new()
		rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rank_row.add_child(rv)
		var drp := int(res.get("rp1", 0)) - int(res.get("rp0", 0))
		var rip := _bar(rv, 12.0, WARN)
		var rr := _label(rv, "%s  ->  %s    (%+d RP)" % [str(D.RANKS[int(res.get("ri0", 0))][1]), str(D.RANKS[int(res.get("ri1", 0))][1]), drp], 16, GOOD if drp >= 0 else BAD)
		rr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var flare := ColorRect.new()
		flare.color = Color(1.0, 0.85, 0.35, 0.55)
		flare.mouse_filter = Control.MOUSE_FILTER_IGNORE
		flare.visible = int(res.get("ri1", 0)) > int(res.get("ri0", 0))
		res_box.add_child(flare)
		flare.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rank_row.pivot_offset = Vector2(60, 34)
		var tw2 := create_tween()
		tw2.tween_property(rip, "value", 1.0, 1.3).from(0.0).set_delay(0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		if flare.visible:
			tw2.tween_property(rank_row, "scale", Vector2(1.35, 1.35), 0.3).from(Vector2(0.7, 0.7)).set_delay(1.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw2.parallel().tween_property(flare, "modulate:a", 0.0, 1.1).from(1.0).set_delay(1.7)
	if int(res.get("bp", 0)) > 0 or true:
		_label(res_box, "BATTLE PASS: +%d points earned this battle" % int(res.get("bp", 0)), 14, Color(0.86, 0.69, 0.22)).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var gotcha := _label(res_box, "Progress is saved to your password account.", 11, TEXT_DIM)
	gotcha.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var back := _make_button(res_box, "BACK TO PORT", 20, Vector2(0, 56))
	back.pressed.connect(func():
		results_root.visible = false
		audio_click())
	var tw := create_tween()
	tw.tween_property(xp_res, "value", clampf(float(int(res.get("xp_have", 0))) / float(maxi(int(res.get("xp_need", 1)), 1)), 0.0, 1.0), 1.3).from(0.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if lvl_gain > 0:
		tw.tween_property(lvl_lbl, "scale", Vector2(1.3, 1.3), 0.3).from(Vector2(0.7, 0.7)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
# ---------------- menu helpers (tier select, ranked, meta) ----------------

func _fill_menu_cards(tier: int) -> void:
	_clear(fleet_grid)
	menu_cards.clear()
	var lvl := D.level_from_xp(int(S.d.get("xp", 0)))
	var opts := D.of_tier(tier)
	for def in opts:
		var d: Dictionary = def
		var locked := not D.unlocked(d, lvl)
		var played := S.has_played(str(d["id"]))
		var txt: String = "Level %d" % int(d.get("lvl", 1)) if locked else ("SERVED ON THIS HULL" if played else "NOT FLOWN YET")
		var cd := _ship_card(d, txt, _fleet_pick.bind(str(d["id"])), 240.0, true)
		if locked:
			cd.modulate = Color(1, 1, 1, 0.4)
		elif not played:
			cd.modulate = Color(0.72, 0.72, 0.76, 0.92)
		fleet_grid.add_child(cd)
	_select_tier_hl(tier)
	_refresh_menu_meta()

func _sel_tier(t: int) -> void:
	menu_tier = clampi(t, 1, D.MAX_TIER)
	_fill_menu_cards(menu_tier)

func _select_tier_hl(t: int) -> void:
	var idx := 1
	for ch in tier_row.get_children():
		ch.modulate = Color(1.0, 0.8, 0.35) if idx == menu_tier else Color(1, 1, 1, 0.55)
		idx += 1

func _toggle_ranked() -> void:
	S.d["ranked_mode"] = not S.b("ranked_mode")
	S.save_file()
	audio_click()
	_refresh_menu_meta()

func _refresh_menu_meta() -> void:
	var meta := D.level_progress(int(S.d.get("xp", 0)))
	var nick := str(S.d.get("nick", "Captain"))
	if name_edit != null and not str(name_edit.text).strip_edges().is_empty():
		nick = str(name_edit.text).strip_edges()
	profile_lbl.text = "%s   -   Level %d   -   %d / %d XP" % [nick, int(meta["lvl"]), int(meta["have"]), int(meta["need"])]
	rank_lbl.text = "RANK: %s" % str(D.rank_from_rp(int(S.d.get("rp", 0))))
	meta_bar.value = clampf(float(meta["have"]) / float(maxi(int(meta["need"]), 1)), 0.0, 1.0)
	ranked_btn.text = "RANKED: ON" if S.b("ranked_mode") else "RANKED: OFF"
	ranked_btn.modulate = Color(1.0, 0.78, 0.35) if S.b("ranked_mode") else Color(1, 1, 1, 0.85)

func _on_play_clicked() -> void:
	if play_btn.disabled:
		return
	name_edit.release_focus()
	var start := "pt_boat"
	if not D.of_tier(1).is_empty():
		start = str(D.of_tier(1)[0]["id"])
	play_pressed.emit(name_edit.text, start)

# ---------------- Settings ----------------

func _page_configs() -> Control:
	var pg := Control.new()
	pg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_box.add_child(pg)
	_rect(pg, 0, 0, 0, 0, 0, 0, 0, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pg.add_child(v)
	_rect(v, 0, 0, 0, 0, 0, 0, 0, 0)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := _label(head, "SETTINGS", 30, Color.WHITE)
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var back := _make_button(head, "BACK TO PORT", 15, Vector2(170, 44), Color(0.3, 0.34, 0.4))
	back.pressed.connect(_goto.bind("home"))
	var tabs := _make_settings_tabs()
	tabs.custom_minimum_size = Vector2(0, 0)
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(tabs)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 10)
	v.add_child(brow)
	var reset := _make_button(brow, "Reset to defaults", 15, Vector2(200, 40), Color(0.5, 0.25, 0.22))
	reset.pressed.connect(_reset_settings)
	var notice := _label(brow, "Esc in battle opens the battle menu with the exit option.", 12, TEXT_DIM)
	notice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notice.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return pg

func _make_settings_tabs() -> TabContainer:
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(640, 380)

	var a := _tab(tabs, "Audio")
	_s_check(a, "Mute all sound", "mute")
	_s_slider(a, "Master volume", "vol_master", 0.0, 1.0, 0.05, true)
	_s_slider(a, "Effects volume", "vol_sfx", 0.0, 1.0, 0.05, true)
	_s_slider(a, "Ocean ambience", "vol_amb", 0.0, 1.0, 0.05, true)
	_s_slider(a, "Engine / rotor volume", "vol_eng", 0.0, 1.0, 0.05, true)

	var g := _tab(tabs, "Graphics")
	_s_option(g, "Graphics quality", "quality", ["Low", "Medium", "High", "Auto"], [0, 1, 2, 3])
	_s_check(g, "Pre-rendered ships and islands (faster; needs restart)", "bake")
	_s_check(g, "Anti-aliasing (MSAA)", "msaa")
	_s_check(g, "Ship shadows", "shadows")
	_s_check(g, "Wake trails", "wakes")
	_s_slider(g, "Effects density", "fx_density", 0.2, 1.0, 0.05, true)
	_s_slider(g, "Screen shake", "shake", 0.0, 1.0, 0.05, true)
	_s_option(g, "FPS limit", "fps_cap", ["Unlimited", "30", "60", "120"], [0, 30, 60, 120])
	_s_check(g, "V-Sync", "vsync")
	_s_check(g, "Fullscreen", "fullscreen")
	_s_check(g, "Show FPS counter", "show_fps")
	_s_slider(g, "Menu / HUD size", "ui_scale", 0.7, 1.8, 0.1, false)
	set_ctrls["ui_scale"]["c"].value_changed.connect(func(_v: float): _apply_ui_scale())

	var p2 := _tab(tabs, "Gameplay")
	_s_slider(p2, "Number of AI ships", "bots", 4.0, 50.0, 1.0, false)
	_s_option(p2, "AI difficulty", "difficulty", ["Easy", "Normal", "Hard"], [0, 1, 2])
	_s_check(p2, "Fog of war (hide ships you have not spotted)", "fog")
	_s_check(p2, "Show ship names", "names")
	_s_check(p2, "Show health bars", "hpbars")
	_s_check(p2, "Show damage numbers", "dmgnums")
	_s_check(p2, "Show aim line", "aimline")
	_s_check(p2, "Show minimap", "minimap")
	_s_slider(p2, "Mouse-wheel zoom speed", "zoom_sens", 0.5, 2.0, 0.1, false)

	var c := _tab(tabs, "Controls")
	for action in SettingsScript.KEY_LABELS.keys():
		var row := HBoxContainer.new()
		c.add_child(row)
		var l := _label(row, str(SettingsScript.KEY_LABELS[action]), 14)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var kb := _make_button(row, _key_name(str(action)), 14, Vector2(150, 30), Color(0.2, 0.3, 0.45))
		kb.pressed.connect(_start_rebind.bind(str(action), kb))
		key_btns[str(action)] = kb
	var note := _label(c, "Fire with the left or right mouse button too. Number keys 1-9 pick weapons. Click a key, then press the new key (Esc cancels).", 12, TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(560, 0)
	return tabs

func _build_settings() -> void:
	settings_root = Control.new()
	root.add_child(settings_root)
	settings_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0.02, 0.06, 0.6)
	settings_root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	settings_root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var card := _panel(center, Color(0.03, 0.08, 0.15, 0.97), 16.0, 14)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	card.add_child(v)
	var t := _label(v, "Settings", 26)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_make_settings_tabs())
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 10)
	v.add_child(brow)
	exit_btn = _make_button(brow, "EXIT BATTLE  (calculate result)", 15, Vector2(300, 40), Color(0.62, 0.28, 0.18))
	exit_btn.visible = false
	exit_btn.pressed.connect(_exit_battle)
	var reset := _make_button(brow, "Reset to defaults", 15, Vector2(200, 40), Color(0.5, 0.25, 0.22))
	reset.pressed.connect(_reset_settings)
	var close := _make_button(brow, "Close  (Esc)", 16, Vector2(0, 40))
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close.pressed.connect(close_settings)
	settings_root.visible = false

func _exit_battle() -> void:
	close_settings()
	exit_requested.emit()

func _tab(tabs: TabContainer, title: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = title
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	sc.add_child(v)
	return v

func _s_row(parent: Node, label: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var l := _label(row, label, 14)
	l.custom_minimum_size = Vector2(230, 0)
	return row

func _s_check(parent: Node, label: String, key: String) -> void:
	var row := _s_row(parent, label)
	var cb := CheckBox.new()
	cb.focus_mode = Control.FOCUS_NONE
	row.add_child(cb)
	cb.toggled.connect(func(on: bool):
		S.d[key] = on
		setting_changed.emit(key))
	set_ctrls[key] = {"t": "check", "c": cb}

func _s_slider(parent: Node, label: String, key: String, mn: float, mx: float, step: float, pct: bool) -> void:
	var row := _s_row(parent, label)
	var sl := HSlider.new()
	sl.min_value = mn
	sl.max_value = mx
	sl.step = step
	sl.custom_minimum_size = Vector2(240, 22)
	sl.focus_mode = Control.FOCUS_NONE
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sl)
	var vl := _label(row, "", 13, TEXT_DIM)
	vl.custom_minimum_size = Vector2(50, 0)
	var is_int := step >= 1.0
	sl.value_changed.connect(func(val: float):
		S.d[key] = int(val) if is_int else val
		vl.text = ("%d%%" % int(val * 100.0)) if pct else (str(int(val)) if is_int else "%.1f" % val)
		setting_changed.emit(key))
	set_ctrls[key] = {"t": "slider", "c": sl, "l": vl, "pct": pct, "int": is_int}

func _s_option(parent: Node, label: String, key: String, names: Array, values: Array) -> void:
	var row := _s_row(parent, label)
	var ob := OptionButton.new()
	ob.focus_mode = Control.FOCUS_NONE
	ob.custom_minimum_size = Vector2(160, 28)
	for n in names:
		ob.add_item(str(n))
	row.add_child(ob)
	ob.item_selected.connect(func(idx: int):
		S.d[key] = values[idx]
		setting_changed.emit(key))
	set_ctrls[key] = {"t": "option", "c": ob, "v": values}

func _start_rebind(action: String, btn: Button) -> void:
	if rebind_action != "":
		rebind_btn.text = _key_name(rebind_action)
	rebind_action = action
	rebind_btn = btn
	btn.text = "Press a key..."

func _sync_settings() -> void:
	for k in set_ctrls.keys():
		var e: Dictionary = set_ctrls[k]
		match str(e["t"]):
			"check":
				var cb: CheckBox = e["c"]
				cb.set_pressed_no_signal(bool(S.d[k]))
			"slider":
				var sl: HSlider = e["c"]
				sl.set_value_no_signal(float(S.d[k]))
				var vl: Label = e["l"]
				var val := float(S.d[k])
				vl.text = ("%d%%" % int(val * 100.0)) if bool(e["pct"]) else (str(int(val)) if bool(e["int"]) else "%.1f" % val)
			"option":
				var ob: OptionButton = e["c"]
				var vals: Array = e["v"]
				ob.select(maxi(vals.find(S.d[k]), 0))
	for a in key_btns.keys():
		var kb: Button = key_btns[a]
		kb.text = _key_name(str(a))

func _reset_settings() -> void:
	S.reset_all()
	_sync_settings()
	_update_hint()
	setting_changed.emit("_reset")

func open_settings() -> void:
	_sync_settings()
	if exit_btn != null:
		exit_btn.visible = in_battle and game != null
	settings_root.visible = true
	settings_open = true

func close_settings() -> void:
	rebind_action = ""
	settings_root.visible = false
	settings_open = false

# ---------------- Public API ----------------

func show_menu() -> void:
	menu_root.visible = true
	hud_root.visible = false
	if leave_btn != null:
		leave_btn.visible = false
	respawn_root.visible = false
	levelup_root.visible = false
	promo_banner.visible = false
	if results_root != null:
		results_root.visible = false
	if login_root != null:
		login_root.visible = not S.logged_in and not guest_mode
	if join_root != null:
		join_root.visible = false
	_refresh_menu_meta()
	_fill_menu_cards(menu_tier)
	_fill_progress()
	_fill_profile()
	_goto(page, true)

func show_game() -> void:
	menu_root.visible = false
	hud_root.visible = true
	respawn_root.visible = false
	leave_btn.visible = in_battle

func set_fps_visible(v: bool) -> void:
	lbl_fps.visible = v

func set_minimap_visible(v: bool) -> void:
	map_panel.visible = v

func add_feed(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", TEXT)
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feed_box.add_child(l)
	feed.append({"label": l, "t": 5.0})
	while feed.size() > 5:
		var old: Dictionary = feed.pop_front()
		var ol: Label = old["label"]
		ol.queue_free()

func hit_flash(k: float) -> void:
	if flash_rect == null:
		return
	flash_rect.modulate.a = clampf(maxf(flash_rect.modulate.a, 0.25 + k * 0.55), 0.0, 0.8)
	if flash_tween != null and flash_tween.is_valid():
		flash_tween.kill()
	flash_tween = create_tween()
	flash_tween.tween_property(flash_rect, "modulate:a", 0.0, 0.55)

func toast(text: String) -> void:
	toast_lbl.text = text
	toast_lbl.modulate.a = 1.0
	if toast_tween != null and toast_tween.is_valid():
		toast_tween.kill()
	toast_tween = create_tween()
	toast_tween.tween_interval(1.6)
	toast_tween.tween_property(toast_lbl, "modulate:a", 0.0, 0.6)

# Called ~10x per second with a snapshot dictionary from main.gd
func refresh(d: Dictionary) -> void:
	if lbl_fps.visible:
		lbl_fps.text = "%d FPS   |   Graphics: %s" % [int(d["fps"]), str(d["quality"])]
	if not hud_root.visible:
		return
	map = d
	map_ctrl.queue_redraw()
	_refresh_board(d["board"])
	if not bool(d["alive"]):
		return
	lbl_class.text = str(d["cname"])
	lbl_level.text = "Tier %s" % str(d["roman"])
	lbl_score.text = "Score  %d" % int(d["score"])
	lbl_next.text = str(d["next_text"])
	bar_xp.value = float(d["progress"])
	var hp := float(d["hp"])
	bar_hp.value = hp
	hp_fill_sb.bg_color = GOOD if hp > 0.4 else BAD
	lbl_hp.text = str(d["hp_text"])
	bar_thr.value = float(d["throttle"])
	var st_txt := ""
	if bool(d["fire"]):
		st_txt = "FIRE ON BOARD"
	if bool(d["flood"]):
		st_txt += ("   " if st_txt != "" else "") + "FLOODING"
	lbl_status.text = st_txt
	warn_lbl.visible = d.has("border") and float(d["border"]) > 0.05
	var dying := hp < 0.28
	if lowhp_rect.visible != dying:
		lowhp_rect.visible = dying
	if dying:
		lowhp_rect.modulate.a = 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.006)
	lbl_status.visible = st_txt != ""
	var ws: Array = d["w"]
	for i in mini(ws.size(), w_slots.size()):
		var st: Dictionary = ws[i]
		var sl: Dictionary = w_slots[i]
		var cd: ColorRect = sl["cd"]
		cd.size.y = 56.0 * float(st["cd"])
		var cl: Label = sl["cnt"]
		cl.text = "%d/%d" % [int(st["ready"]), int(st["total"])] if int(st["total"]) > 1 else ""
	if int(d["wsel"]) != sel_idx:
		set_selected(int(d["wsel"]))
	var abs_: Array = d["ab"]
	for i in mini(abs_.size(), ab_slots.size()):
		var ab: Dictionary = abs_[i]
		var asl: Dictionary = ab_slots[i]
		var acd: ColorRect = asl["cd"]
		acd.size.y = 52.0 * float(ab["cd"])
		var sc: Control = asl["slot"]
		if bool(sc.get_meta("on")) != bool(ab["on"]):
			sc.set_meta("on", bool(ab["on"]))
			sc.queue_redraw()
	var ai: Dictionary = d["air"]
	if not ai.is_empty():
		air_panel.visible = true
		var stt := int(ai["state"])
		air_title.text = "%s   [%s]" % [str(ai["name"]), _key_name("air")]
		air_bar.value = float(ai["hp"])
		if stt == 2:
			air_state.text = "Rebuilding... %d s" % int(ceilf(float(ai["cd"])))
			air_state.add_theme_color_override("font_color", WARN)
		elif stt == 1:
			air_state.text = "CONTROLLING  -  %s returns to ship" % _key_name("air")
			air_state.add_theme_color_override("font_color", GOOD)
		else:
			air_state.text = "Following your ship  -  press %s to fly" % _key_name("air")
			air_state.add_theme_color_override("font_color", TEXT_DIM)
		if bool(ai["warn"]):
			air_state.text = "Out of range - returning!"
		if d.has("squad_n") and int(d["squad_n"]) > 1:
			air_state.text += "   |   Squadron %d/%d in the air" % [int(d["squad_alive"]), int(d["squad_n"])]
		lbl_ctrl.text = "AIRCRAFT CONTROL  -  your ship is on AUTOPILOT (retreating and defending)" if stt == 1 else ""
	else:
		air_panel.visible = false
		lbl_ctrl.text = ""

func _refresh_board(board: Array) -> void:
	var sig := str(board)
	if sig == last_board_sig:
		return
	last_board_sig = sig
	for i in lb_rows.size():
		var r: Array = lb_rows[i]
		var row: Control = r[0]
		if i >= board.size():
			row.visible = false
			continue
		row.visible = true
		var e: Array = board[i]
		var rn: Label = r[1]
		var rs: Label = r[2]
		rn.text = "%d. %s" % [int(e[0]), str(e[1])]
		rs.text = "%s  %d" % [str(D.ROMAN[int(e[4]) - 1]), int(e[2])]
		var col := Color(0.55, 0.88, 1.0) if bool(e[3]) else TEXT
		rn.add_theme_color_override("font_color", col)

func _icon_missile(c: Control, ctr: Vector2, body: Color, nose: Color, ln: float, wing: Color, span: float) -> void:
	c.draw_rect(Rect2(ctr + Vector2(-ln, -3.0), Vector2(ln * 1.5, 6.0)), body)
	c.draw_colored_polygon(PackedVector2Array([ctr + Vector2(ln * 0.5, -3.0), ctr + Vector2(ln * 0.5 + 8.0, 0.0), ctr + Vector2(ln * 0.5, 3.0)]), nose)
	c.draw_colored_polygon(PackedVector2Array([ctr + Vector2(-ln * 0.2, -3.0), ctr + Vector2(-ln * 0.7, -3.0), ctr + Vector2(-ln * 0.7, -span * 0.5)]), wing)
	c.draw_colored_polygon(PackedVector2Array([ctr + Vector2(-ln * 0.2, 3.0), ctr + Vector2(-ln * 0.7, 3.0), ctr + Vector2(-ln * 0.7, span * 0.5)]), wing)
	c.draw_line(ctr + Vector2(-ln, 0.0), ctr + Vector2(-ln - 6.0, 0.0), Color(1.0, 0.65, 0.2), 3.0)

# The world (ships, turrets, islands) is rendered into textures once at start-up; this shows progress.
func set_loading(f: float) -> void:
	loading = f
	if play_btn == null:
		return
	play_btn.disabled = f < 1.0
	play_btn.text = "Play" if f >= 1.0 else "Preparing the world...  %d%%" % int(f * 100.0)
