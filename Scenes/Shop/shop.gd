extends Control
class_name ShopUI

signal continue_pressed()

var title      : Label
var offers_row : HBoxContainer
var reroll_btn : Button
var cont_btn   : Button
var biscuits_l : Label

var offers_grid: GridContainer
var offers_wrap: MarginContainer

# Pulled from UpgradeDB at runtime; falls back to a sane default if DB empty.
var OFFER_KEYS: Array[String] = []
const SLOTS := 3  # offer cards; a 4th "stats" card is auto-added

var _offers      : Array[String] = []
var _slot_locked : Array[bool]   = [false, false, false]
var _reroll_cost : int           = 2
var _rng         : RandomNumberGenerator = RandomNumberGenerator.new()

var _card_ui: Array = []  # per-card refs for refresh

# --- Stats card refs ---
var _stats_card  : PanelContainer
var _stats_vbox  : VBoxContainer
var _stats_label : RichTextLabel

# --- Responsive thresholds & card sizing ---
const CARD_MIN_W   := 180.0
const CARD_MAX_W   := 320.0
const CARD_MIN_H   := 360
const CARD_MAX_H   := 360.0 * 2
const GRID_GAP     := 64
const EDGE_PADDING := 48.0  # screen edge padding in pixels

func _ready() -> void:
	_rng.randomize()
	_bind_refs()
	_make_fullscreen_layout()
	_ensure_offers_grid()

	# Pull keys ASAP if DB is already ready; otherwise wait for it.
	if typeof(UpgradeDB) != TYPE_NIL:
		if UpgradeDB.is_ready():
			OFFER_KEYS = UpgradeDB.keys_sorted()
		else:
			# Build once with fallbacks; refresh to real data when DB finishes.
			UpgradeDB.db_ready.connect(_on_db_ready)
	if OFFER_KEYS.is_empty():
		OFFER_KEYS = ["damage","firerate","range","pickup","projectiles","movespeed"]

	# Title
	if title:
		title.text = "Shop — Risk it for the Biscuit"

	# Wire buttons
	if reroll_btn:
		reroll_btn.custom_minimum_size.y = 48
		reroll_btn.pressed.connect(_on_reroll)
	if cont_btn:
		cont_btn.custom_minimum_size.y = 48
		cont_btn.pressed.connect(_on_continue)

	GameState.biscuits_changed.connect(_refresh_biscuits)
	GameState.upgrades_changed.connect(_on_upgrades_changed)

	# HTML5 timing: build next frame so autoloads/layout exist.
	call_deferred("_first_build")

	resized.connect(_on_resized)
	_on_resized()

func _on_db_ready() -> void:
	# DB finished loading; switch to authoritative key order & re-render.
	OFFER_KEYS = UpgradeDB.keys_sorted()
	_generate_if_needed()
	_render_offers()
	_refresh_biscuits()

func _first_build() -> void:
	_generate_if_needed()
	_render_offers()
	_refresh_biscuits()

# ---------- Node binding ----------
func _bind_refs() -> void:
	title      = _find_node_as("Title", "Label")            as Label
	offers_row = _find_node_as("Offers", "HBoxContainer")   as HBoxContainer
	reroll_btn = _find_node_as("Reroll", "Button")          as Button
	cont_btn   = _find_node_as("Continue", "Button")        as Button
	biscuits_l = _find_node_as("Biscuits", "Label")         as Label

	if not title:      push_warning("ShopUI.gd: Missing 'Title'")
	if not reroll_btn: push_warning("ShopUI.gd: Missing 'Reroll'")
	if not cont_btn:   push_warning("ShopUI.gd: Missing 'Continue'")
	if not biscuits_l: push_warning("ShopUI.gd: Missing 'Biscuits'")

func _find_node_as(name:String, type_name:String) -> Node:
	var n: Node = get_node_or_null(NodePath("Panel/VBox/"+name))
	if n and n.is_class(type_name):
		return n
	n = get_node_or_null(NodePath(name))
	if n and n.is_class(type_name):
		return n
	var queue: Array[Node] = [self]
	while queue.size() > 0:
		var cur: Node = queue.pop_front()
		if cur.name == name and cur.is_class(type_name):
			return cur
		for c in cur.get_children():
			queue.push_back(c as Node)
	return null

# ---------- Build fullscreen + grid ----------
func _make_fullscreen_layout() -> void:
	anchors_preset = Control.PRESET_FULL_RECT
	offset_left = 0; offset_top = 0; offset_right = 0; offset_bottom = 0

	# Soft backdrop
	if not get_node_or_null("Backdrop"):
		var bg: ColorRect = ColorRect.new()
		bg.name = "Backdrop"
		bg.color = Color(0,0,0,0.35)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)

	# Title style
	if title:
		title.add_theme_font_size_override("font_size", 32)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		title.custom_minimum_size.y = 56

func _ensure_offers_grid() -> void:
	var parent_node: Node = null
	var insert_index: int = -1
	if offers_row and offers_row.get_parent():
		parent_node = offers_row.get_parent()
		insert_index = offers_row.get_index()
		offers_row.visible = false

	if offers_wrap == null:
		offers_wrap = MarginContainer.new()
		offers_wrap.name = "OffersWrap"
		offers_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		offers_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
		offers_wrap.add_theme_constant_override("margin_left", EDGE_PADDING)
		offers_wrap.add_theme_constant_override("margin_right", EDGE_PADDING)
		offers_wrap.add_theme_constant_override("margin_top", EDGE_PADDING)
		offers_wrap.add_theme_constant_override("margin_bottom", EDGE_PADDING)

		if parent_node and parent_node is Container:
			(parent_node as Container).add_child(offers_wrap)
			if insert_index >= 0:
				(parent_node as Container).move_child(offers_wrap, insert_index)
		else:
			add_child(offers_wrap)

	if offers_grid == null:
		offers_grid = GridContainer.new()
		offers_grid.name = "OffersGrid"
		offers_grid.columns = 3
		offers_grid.add_theme_constant_override("h_separation", GRID_GAP)
		offers_grid.add_theme_constant_override("v_separation", GRID_GAP)
		offers_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		offers_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
		offers_wrap.add_child(offers_grid)

# ---------- Responsive reflow ----------
func _on_resized() -> void:
	var vp_w: float = get_viewport_rect().size.x
	var content_w: float = max(0.0, vp_w - (EDGE_PADDING * 2.0))
	var cols_fit := int(floor((content_w + GRID_GAP) / (CARD_MIN_W + GRID_GAP)))
	var total_cards := SLOTS + 1
	var cols: int = clamp(cols_fit, 1, min(6, total_cards))
	if offers_grid:
		offers_grid.columns = cols
	_update_card_sizes(cols)

func _update_card_sizes(cols: int) -> void:
	if offers_grid == null:
		return
	var vp_size: Vector2 = get_viewport_rect().size
	var avail_size := Vector2(
		max(0.0, vp_size.x - (EDGE_PADDING * 2.0)),
		max(0.0, vp_size.y - (EDGE_PADDING * 2.0))
	)
	var padding: float = float((cols - 1) * GRID_GAP)
	var usable_w: float = max(0.0, avail_size.x - padding)
	var card_w: float = clamp(usable_w / float(cols), CARD_MIN_W, CARD_MAX_W)
	var card_h: float = clamp(avail_size.y * 0.48, CARD_MIN_H, CARD_MAX_H)

	for c in offers_grid.get_children():
		var card := c as PanelContainer
		if card:
			card.custom_minimum_size = Vector2(card_w, card_h)

# ---------- UI / Flow ----------
func _refresh_biscuits(_t:int=0, _d:int=0) -> void:
	if biscuits_l:
		biscuits_l.add_theme_font_size_override("font_size", 20)
		biscuits_l.text = "Biscuits: %d   Reroll: %d" % [GameState.biscuits, _reroll_cost]
	_refresh_card_buttons()
	_refresh_reroll_button()
	_refresh_stats_card()

func _on_upgrades_changed() -> void:
	_render_offers()

func _generate_if_needed() -> void:
	if _offers.size() == SLOTS:
		return
	_offers = _roll_offers(SLOTS)

func _roll_offers(n:int) -> Array[String]:
	# Build a shuffled pool from DB keys (or fallback OFFER_KEYS)
	var pool: Array[String] = []
	for k in OFFER_KEYS:
		pool.append(String(k))
	pool.shuffle()
	var picks: Array[String] = []
	while picks.size() < n and pool.size() > 0:
		picks.append(pool.pop_back())
	return picks

func _render_offers() -> void:
	if offers_grid == null:
		return

	# Clear grid
	for n in offers_grid.get_children():
		(n as Node).queue_free()

	_card_ui.clear()
	_stats_card = null
	_stats_vbox = null
	_stats_label = null

	# --- Build offer cards ---
	for i in range(SLOTS):
		if i >= _offers.size():
			break
		var key: String = _offers[i]
		# On web, don't skip if DB isn't ready; fallbacks render fine.

		var lvl: int = GameState.get_upgrade(key, 0)
		var max_lvl: int = _get_max_level(key)

		var card: PanelContainer = _make_card_container()
		offers_grid.add_child(card)

		var vb: VBoxContainer = VBoxContainer.new()
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vb.add_theme_constant_override("separation", 8)
		card.add_child(vb)

		var name_label: Label = Label.new()
		name_label.text = _upgrade_title(key, lvl, max_lvl)
		name_label.add_theme_font_size_override("font_size", 22)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.custom_minimum_size.y = 32
		vb.add_child(name_label)

		var desc: Label = Label.new()
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.text = _upgrade_desc(key)
		desc.add_theme_font_size_override("font_size", 16)
		desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		desc.size_flags_vertical = Control.SIZE_EXPAND
		vb.add_child(desc)

		var buttons: HBoxContainer = HBoxContainer.new()
		buttons.add_theme_constant_override("separation", 8)
		buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vb.add_child(buttons)

		# Per-item LOCK (toggle)
		var lock_button: Button = Button.new()
		lock_button.toggle_mode = true
		lock_button.button_pressed = _slot_locked[i]
		lock_button.text = "Unlock" if _slot_locked[i] else "Lock"
		lock_button.custom_minimum_size = Vector2(0, 40)
		lock_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lock_button.pressed.connect(_on_lock_toggled.bind(i, lock_button))
		buttons.add_child(lock_button)

		# BUY
		var buy_btn: Button = Button.new()
		buy_btn.custom_minimum_size = Vector2(0, 40)
		buy_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buy_btn.pressed.connect(_on_buy.bind(i))
		buttons.add_child(buy_btn)

		# Cache refs for later refresh
		_card_ui.append({
			"index": i,
			"key": key,
			"name": name_label,
			"buy": buy_btn,
			"lock": lock_button
		})

	# --- Stats card (4th card) ---
	_add_stats_card()

	# First paint of texts/enabled state
	_refresh_card_buttons()
	_refresh_reroll_button()
	_refresh_stats_card()

	# Re-apply sizes after rebuilding
	_on_resized()

func _make_card_container() -> PanelContainer:
	var card: PanelContainer = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical   = 0

	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.09, 0.12, 0.95)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.18, 0.22, 0.28, 1.0)
	sb.set_content_margin_all(12.0)

	card.add_theme_stylebox_override("panel", sb)
	return card

# ---------- Stats card helpers ----------
func _add_stats_card() -> void:
	_stats_card = _make_card_container()
	offers_grid.add_child(_stats_card)

	_stats_vbox = VBoxContainer.new()
	_stats_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stats_vbox.add_theme_constant_override("separation", 8)
	_stats_card.add_child(_stats_vbox)

	var name_label: Label = Label.new()
	name_label.text = "Current Build"
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.custom_minimum_size.y = 32
	_stats_vbox.add_child(name_label)

	_stats_label = RichTextLabel.new()
	_stats_label.fit_content = true
	_stats_label.bbcode_enabled = true
	_stats_label.scroll_active = false
	_stats_label.selection_enabled = false
	_stats_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats_label.size_flags_vertical = Control.SIZE_EXPAND
	_stats_vbox.add_child(_stats_label)

func _refresh_stats_card() -> void:
	if _stats_label == null:
		return
	_stats_label.clear()
	_stats_label.append_text(_build_stats_text())

func _build_stats_text() -> String:
	if GameState.has_method("get_all_stats"):
		var all: Dictionary = GameState.get_all_stats() as Dictionary
		var keys: Array = all.keys()
		keys.sort()
		var out_text: String = ""
		for i in keys.size():
			var k = keys[i]
			out_text += "[b]%s:[/b] %s" % [str(k).capitalize(), str(all[k])]
			if i < keys.size() - 1:
				out_text += "\n"
		return out_text

	var out2: String = ""
	for i in OFFER_KEYS.size():
		var key: String = OFFER_KEYS[i]
		var label: String = str(key).capitalize()
		var text: String = str(GameState.get_stat(key))
		out2 += "[b]%s:[/b] %s" % [label, text]
		if i < OFFER_KEYS.size() - 1:
			out2 += "\n"
	return out2

# ---------- Actions ----------
func _on_lock_toggled(index:int, btn:Button) -> void:
	_slot_locked[index] = btn.button_pressed
	btn.text = "Unlock" if btn.button_pressed else "Lock"
	_refresh_card_buttons()
	_refresh_reroll_button()

func _on_buy(index:int) -> void:
	if index < 0 or index >= _offers.size():
		return
	var key: String = _offers[index]
	var lvl: int = GameState.get_upgrade(key, 0)
	var max_lvl: int = _get_max_level(key)
	if lvl >= max_lvl:
		return

	var cost: int = GameState.get_upgrade_cost(key)
	if not GameState.spend_biscuits(cost):
		return
	GameState.set_upgrade(key, lvl + 1)

	if not _slot_locked[index]:
		var replacement: Array[String] = _roll_offers(1)
		if replacement.size() > 0:
			_offers[index] = replacement[0]

	_render_offers()
	_refresh_biscuits()

func _on_reroll() -> void:
	if not GameState.spend_biscuits(_reroll_cost):
		return
	for i in range(_offers.size()):
		if not _slot_locked[i]:
			var repl: Array[String] = _roll_offers(1)
			if repl.size() > 0:
				_offers[i] = repl[0]
	_reroll_cost += 1
	_render_offers()
	_refresh_biscuits()

func _on_continue() -> void:
	emit_signal("continue_pressed")

# ---------- Pretty text / helpers ----------
func _upgrade_title(key:String, lvl:int, max_lvl:int) -> String:
	var name := key.capitalize()
	if typeof(UpgradeDB) != TYPE_NIL and UpgradeDB.has(key):
		var def: Resource = UpgradeDB.get_def(key)
		if def:
			name = _res_str(def, "display_name", name)
	return "%s  (Lv %d/%d)" % [name, lvl, max_lvl]

func _upgrade_desc(key:String) -> String:
	if typeof(UpgradeDB) != TYPE_NIL and UpgradeDB.has(key):
		var def: Resource = UpgradeDB.get_def(key)
		if def:
			return _res_str(def, "description", key)
	return key  # fallback

func _get_max_level(key:String) -> int:
	if typeof(UpgradeDB) != TYPE_NIL and UpgradeDB.has(key):
		var def: Resource = UpgradeDB.get_def(key)
		if def:
			var m = def.get("max_level")
			if typeof(m) != TYPE_NIL:
				return int(m)
	return 10  # safe default

func _refresh_card_buttons() -> void:
	for ui in _card_ui:
		var idx: int = int(ui["index"])
		if idx < 0 or idx >= _offers.size():
			continue
		var key: String = _offers[idx]

		var lvl: int = GameState.get_upgrade(key, 0)
		var max_lvl: int = _get_max_level(key)
		var cost: int = GameState.get_upgrade_cost(key)

		var name_label: Label = ui["name"]
		if name_label:
			name_label.text = _upgrade_title(key, lvl, max_lvl)

		var buy_btn: Button = ui["buy"]
		if buy_btn:
			if lvl >= max_lvl:
				buy_btn.text = "MAXED"
				buy_btn.disabled = true
			else:
				buy_btn.text = "Buy (%d)" % cost
				buy_btn.disabled = GameState.biscuits < cost

func _refresh_reroll_button() -> void:
	if reroll_btn:
		reroll_btn.text = "Reroll (%d)" % _reroll_cost
		reroll_btn.disabled = GameState.biscuits < _reroll_cost

func _res_str(res:Resource, prop:String, fallback:String="") -> String:
	if res == null:
		return fallback
	var v = res.get(prop)
	return fallback if typeof(v) == TYPE_NIL else String(v)
