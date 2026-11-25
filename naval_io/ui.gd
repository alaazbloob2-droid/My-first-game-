extends CanvasLayer
# ui.gd - HUD, main menu, promotion / respawn pop-ups and the settings window.
# Everything is built once from Control nodes (retained mode). main.gd pushes values in at
# ~10 Hz through refresh(); nothing here redraws every frame except the kill feed fade.

signal play_pressed(nick: String, ship_id: String)
signal ship_picked(ship_id: String, mode: String)
signal slot_clicked(idx: int)
signal ability_clicked(idx: int)
signal setting_changed(key: String)

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
var menu_ships_row: HBoxContainer
var tier_lbl: Label
var warn_lbl: Label
var map_zone := PackedVector2Array()
var set_ctrls: Dictionary = {}
var rebind_action := ""
var rebind_btn: Button
var key_btns: Dictionary = {}
var last_board_sig := ""

# ---------------- Setup ----------------

func setup(settings: SettingsScript) -> void:
	S = settings
	layer = 10
	root = Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var th := Theme.new()
	th.default_font_size = 14
	root.theme = th
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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
	warn_lbl.visible = false

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

func _build_menu() -> void:
	menu_root = Control.new()
	root.add_child(menu_root)
	menu_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.05, 0.12, 0.45)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(col)

	var title := HBoxContainer.new()
	title.alignment = BoxContainer.ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(title)
	var ta := _label(title, GAME_TITLE_A, 68, Color.WHITE)
	var tb := _label(title, GAME_TITLE_B, 68, ACCENT_HI)
	for t in [ta, tb]:
		t.add_theme_constant_override("outline_size", 8)
		t.add_theme_color_override("font_outline_color", Color(0, 0.05, 0.15, 0.6))
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sub := _label(col, TAGLINE, 16, TEXT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var card := _panel(col, PANEL_BG, 16.0, 14)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 10)
	card.add_child(cv)
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Nickname"
	name_edit.max_length = 14
	name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_edit.custom_minimum_size = Vector2(340, 42)
	name_edit.add_theme_font_size_override("font_size", 19)
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
	cv.add_child(name_edit)
	name_edit.text_submitted.connect(func(_t: String): _on_play_clicked())
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 14)
	prow.alignment = BoxContainer.ALIGNMENT_CENTER
	cv.add_child(prow)
	profile_lbl = _label(prow, "Captain", 14, TEXT)
	rank_lbl = _label(prow, "RANK: Rookie", 14, WARN)
	meta_bar = _bar(prow, 8.0, ACCENT_HI)
	meta_bar.custom_minimum_size = Vector2(210, 8)
	ranked_btn = _make_button(prow, "RANKED: OFF", 13, Vector2(150, 30), Color(0.3, 0.34, 0.4))
	ranked_btn.pressed.connect(_toggle_ranked)
	var pickrow := HBoxContainer.new()
	pickrow.add_theme_constant_override("separation", 8)
	pickrow.alignment = BoxContainer.ALIGNMENT_CENTER
	cv.add_child(pickrow)
	_label(pickrow, "Starting tier:", 13, TEXT_DIM)
	tier_row = HBoxContainer.new()
	tier_row.add_theme_constant_override("separation", 4)
	tier_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cv.add_child(tier_row)
	for t in D.MAX_TIER:
		_make_button(tier_row, str(D.ROMAN[t]), 15, Vector2(42, 32), Color(0.25, 0.29, 0.36)).pressed.connect(_sel_tier.bind(t + 1))
	var pick := _label(cv, "Choose your starting ship", 13, TEXT_DIM)
	pick.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_ships_row = HBoxContainer.new()
	menu_ships_row.add_theme_constant_override("separation", 10)
	menu_ships_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cv.add_child(menu_ships_row)
	_sel_tier(1)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 10)
	cv.add_child(brow)
	var play := _make_button(brow, "Loading world...  0%", 22, Vector2(430, 50))
	play_btn = play
	play.disabled = true
	play.pressed.connect(_on_play_clicked)
	var sbtn := _make_button(brow, "Settings", 18, Vector2(150, 50), Color(0.3, 0.34, 0.4))
	sbtn.pressed.connect(open_settings)

	var how := _panel(col, Color(0.03, 0.08, 0.15, 0.55), 10.0, 12)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 2)
	how.add_child(hv)
	var h1 := _label(hv, "W / S throttle    A / D steer    LMB or Space: fire selected weapon    1-9 or click the bar: choose weapon", 12, TEXT_DIM)
	h1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var h2 := _label(hv, "Q / E abilities    V aircraft (ship goes on autopilot)    AA guns are manual: select an AA weapon and shoot aircraft    Esc settings", 12, TEXT_DIM)
	h2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _select_menu_ship(id: String) -> void:
	if not menu_cards.has(id):
		return
	menu_ship_id = id
	for k in menu_cards.keys():
		var pc: PanelContainer = menu_cards[k]
		var sb := pc.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
		if str(k) == id:
			sb.border_color = ACCENT_HI
			sb.set_border_width_all(3)
		else:
			sb.border_color = Color(1, 1, 1, 0.14)
			sb.set_border_width_all(1)
		pc.add_theme_stylebox_override("panel", sb)

func _fill_menu_cards(tier: int) -> void:
	_clear(menu_ships_row)
	menu_cards.clear()
	var lvl := D.level_from_xp(int(S.d.get("xp", 0)))
	var opts := D.of_tier(tier)
	if not opts.is_empty():
		menu_ship_id = str(opts[0]["id"])
	for def in opts:
		var d: Dictionary = def
		var locked := not D.unlocked(d, lvl)
		var txt := "Level %d" % int(d.get("lvl", 1)) if locked else "Select"
		var cd := _ship_card(d, txt, _select_menu_ship.bind(str(d["id"])), 200.0, true)
		if locked:
			cd.modulate = Color(1, 1, 1, 0.42)
		else:
			menu_cards[str(d["id"])] = cd
		menu_ships_row.add_child(cd)
	_select_menu_ship(menu_ship_id)
	_refresh_menu_meta()

func _sel_tier(t: int) -> void:
	menu_tier = clampi(t, 1, D.MAX_TIER)
	var idx := 1
	for ch in tier_row.get_children():
		ch.modulate = Color(1.0, 0.8, 0.35) if idx == menu_tier else Color(1, 1, 1, 0.55)
		idx += 1
	_refresh_menu_meta()
	_fill_menu_cards(menu_tier)

func _toggle_ranked() -> void:
	S.d["ranked_mode"] = not S.b("ranked_mode")
	S.save_file()
	audio_click()
	_refresh_menu_meta()

func _refresh_menu_meta() -> void:
	var meta := D.level_progress(int(S.d.get("xp", 0)))
	profile_lbl.text = "%s   -   Level %d   -   %d / %d XP" % [name_edit.text.strip_edges() if name_edit.text.strip_edges() != "" else "Captain", meta["lvl"], meta["have"], meta["need"]]
	rank_lbl.text = "RANK: %s" % str(D.rank_from_rp(int(S.d.get("rp", 0))))
	meta_bar.value = clampf(float(meta["have"]) / float(maxi(meta["need"], 1)), 0.0, 1.0)
	ranked_btn.text = "RANKED: ON" if S.b("ranked_mode") else "RANKED: OFF"
	ranked_btn.modulate = Color(1.0, 0.78, 0.35) if S.b("ranked_mode") else Color(1, 1, 1, 0.85)

func _on_play_clicked() -> void:
	if play_btn.disabled:
		return
	name_edit.release_focus()
	play_pressed.emit(name_edit.text, menu_ship_id)

# ---------------- Settings window ----------------

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
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(640, 380)
	v.add_child(tabs)

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

	var p := _tab(tabs, "Gameplay")
	_s_slider(p, "Number of AI ships", "bots", 4.0, 50.0, 1.0, false)
	_s_option(p, "AI difficulty", "difficulty", ["Easy", "Normal", "Hard"], [0, 1, 2])
	_s_check(p, "Fog of war (hide ships you have not spotted)", "fog")
	_s_check(p, "Show ship names", "names")
	_s_check(p, "Show health bars", "hpbars")
	_s_check(p, "Show damage numbers", "dmgnums")
	_s_check(p, "Show aim line", "aimline")
	_s_check(p, "Show minimap", "minimap")
	_s_slider(p, "Mouse-wheel zoom speed", "zoom_sens", 0.5, 2.0, 0.1, false)

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

	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 10)
	v.add_child(brow)
	var reset := _make_button(brow, "Reset to defaults", 15, Vector2(200, 40), Color(0.5, 0.25, 0.22))
	reset.pressed.connect(_reset_settings)
	var close := _make_button(brow, "Close  (Esc)", 16, Vector2(0, 40))
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close.pressed.connect(close_settings)
	settings_root.visible = false

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
	respawn_root.visible = false
	levelup_root.visible = false
	promo_banner.visible = false
	_refresh_menu_meta()
	_fill_menu_cards(menu_tier)
	name_edit.grab_focus()

func show_game() -> void:
	menu_root.visible = false
	hud_root.visible = true
	respawn_root.visible = false

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
