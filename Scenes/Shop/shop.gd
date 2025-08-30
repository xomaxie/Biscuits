extends Control
class_name ShopUI

signal continue_pressed()

# -----------------------------------------------------------------------------
# Node references
# -----------------------------------------------------------------------------
var title: Label
var offers_row: HBoxContainer
var reroll_btn: Button
var cont_btn: Button
var biscuits_l: Label

var offers_grid: GridContainer
var offers_wrap: MarginContainer
var offers_vbox: VBoxContainer
var small_footer: HBoxContainer
var small_reroll_btn: Button
var small_cont_btn: Button

# -----------------------------------------------------------------------------
# Offers & shop state
# -----------------------------------------------------------------------------
var OFFER_KEYS: Array[String] = []
const SLOTS := 3

var _offers: Array[String] = []
var _slot_locked: Array[bool] = [false, false, false]
var _reroll_cost: int = 2
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _card_ui: Array = []
var _has_opened: bool = false

# -----------------------------------------------------------------------------
# Stats card refs
# -----------------------------------------------------------------------------
var _stats_card: PanelContainer
var _stats_vbox: VBoxContainer
var _stats_label: RichTextLabel

# -----------------------------------------------------------------------------
# Layout constants
# -----------------------------------------------------------------------------
const CARD_MIN_W := 180.0
const CARD_MAX_W := 320.0
const CARD_MIN_H := 360.0
const CARD_MAX_H := 720.0
const GRID_GAP := 64
const EDGE_PADDING := 48.0
const EXTRA_TOP_PAD := 64.0
const CARD_CONTENT_TOP := 24.0

@onready var DB: Node = get_node("/root/UpgradeDB")

# -----------------------------------------------------------------------------
# Rarity weights and type bias
# -----------------------------------------------------------------------------
const BASE_RARITY_WEIGHTS := {
	"common": 1.00,
	"uncommon": 0.45,
	"rare": 0.15,
	"legendary": 0.05
}

const TYPE_WEIGHTS := {
	"item": 1.00,
	"weapon": 0.55
}

const LUCK_RARITY_BONUS := {
	"common": Vector2(-0.60, 0.00),
	"uncommon": Vector2(0.40, 0.00),
	"rare": Vector2(0.90, 0.00),
	"legendary": Vector2(1.60, 0.00)
}

# -----------------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------------
func _ready() -> void:
	_rng.randomize()
	_bind_refs()
	_make_fullscreen_layout()
	_ensure_offers_grid()

	if DB and DB.is_ready():
		OFFER_KEYS = DB.keys_sorted()
	else:
		if DB:
			DB.db_ready.connect(_on_db_ready)
	if OFFER_KEYS.is_empty():
		OFFER_KEYS = ["damage", "firerate", "range", "pickup", "projectiles", "movespeed"]

	if title:
		title.text = "Shop — Risk it for the Biscuit"

	# Legacy footer exists in some scenes; we hide it once small footer is ready
	if reroll_btn:
		_apply_flat_button_style(
			reroll_btn,
			Color(0.16, 0.22, 0.28),
			Color(0.36, 0.52, 0.66)
		)
		reroll_btn.custom_minimum_size.y = 48.0
		reroll_btn.pressed.connect(_on_reroll)
	if cont_btn:
		_apply_flat_button_style(
			cont_btn,
			Color(0.16, 0.22, 0.28),
			Color(0.36, 0.52, 0.66)
		)
		cont_btn.custom_minimum_size.y = 48.0
		cont_btn.pressed.connect(_on_continue)

	GameState.biscuits_changed.connect(_refresh_biscuits)
	GameState.upgrades_changed.connect(_on_upgrades_changed)

	call_deferred("_first_build")

	resized.connect(_on_resized)
	_on_resized()

	visibility_changed.connect(_on_visibility_changed)

func _on_db_ready() -> void:
	OFFER_KEYS = DB.keys_sorted()
	_generate_if_needed()
	_render_offers()
	_refresh_biscuits()

func _first_build() -> void:
	_generate_if_needed()
	_render_offers()
	_refresh_biscuits()

# -----------------------------------------------------------------------------
# Visibility → treat as shop opening
# -----------------------------------------------------------------------------
func _on_visibility_changed() -> void:
	if visible:
		if _has_opened:
			_reseed_unlocked_for_new_open(true)
		_has_opened = true

# -----------------------------------------------------------------------------
# Public entry for game flow
# -----------------------------------------------------------------------------
func on_shop_open(reset_reroll_cost: bool = true) -> void:
	_reseed_unlocked_for_new_open(reset_reroll_cost)

# -----------------------------------------------------------------------------
# Node binding
# -----------------------------------------------------------------------------
func _bind_refs() -> void:
	title = _find_node_as("Title", "Label") as Label
	offers_row = _find_node_as("Offers", "HBoxContainer") as HBoxContainer
	reroll_btn = _find_node_as("Reroll", "Button") as Button
	cont_btn = _find_node_as("Continue", "Button") as Button
	biscuits_l = _find_node_as("Biscuits", "Label") as Label

	if not title:
		push_warning("ShopUI.gd: Missing 'Title'")
	if not reroll_btn:
		push_warning("ShopUI.gd: Missing 'Reroll'")
	if not cont_btn:
		push_warning("ShopUI.gd: Missing 'Continue'")
	if not biscuits_l:
		push_warning("ShopUI.gd: Missing 'Biscuits'")

func _find_node_as(name: String, type_name: String) -> Node:
	var n: Node = get_node_or_null(NodePath("Panel/VBox/" + name))
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

# -----------------------------------------------------------------------------
# Layout & grid building
# -----------------------------------------------------------------------------
func _make_fullscreen_layout() -> void:
	anchors_preset = Control.PRESET_FULL_RECT
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0

	if not get_node_or_null("Backdrop"):
		var bg: ColorRect = ColorRect.new()
		bg.name = "Backdrop"
		bg.color = Color(0.0, 0.0, 0.0, 0.35)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)

	if title:
		title.add_theme_font_size_override("font_size", 32)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		title.custom_minimum_size.y = 56.0

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
		offers_wrap.add_theme_constant_override(
			"margin_top",
			EDGE_PADDING + EXTRA_TOP_PAD
		)
		offers_wrap.add_theme_constant_override("margin_bottom", EDGE_PADDING)
		if parent_node and parent_node is Container:
			(parent_node as Container).add_child(offers_wrap)
			if insert_index >= 0:
				(parent_node as Container).move_child(offers_wrap, insert_index)
		else:
			add_child(offers_wrap)

	if offers_vbox == null:
		offers_vbox = VBoxContainer.new()
		offers_vbox.name = "OffersVBox"
		offers_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		offers_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		offers_vbox.add_theme_constant_override("separation", 12)
		offers_wrap.add_child(offers_vbox)

	if offers_grid == null:
		offers_grid = GridContainer.new()
		offers_grid.name = "OffersGrid"
		offers_grid.columns = 3
		offers_grid.add_theme_constant_override("h_separation", GRID_GAP)
		offers_grid.add_theme_constant_override("v_separation", GRID_GAP)
		offers_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		offers_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
		offers_vbox.add_child(offers_grid)

	_ensure_small_footer()
	_hide_legacy_footer()
	_toggle_small_footer()

# -----------------------------------------------------------------------------
# Small-screen footer helpers
# -----------------------------------------------------------------------------
func _is_small_screen() -> bool:
	var vp: Vector2 = get_viewport_rect().size
	return vp.x < 1920.0 or vp.y < 1080.0

func _ensure_small_footer() -> void:
	if small_footer:
		return
	if offers_vbox == null:
		return

	small_footer = HBoxContainer.new()
	small_footer.name = "SmallFooter"
	small_footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	small_footer.alignment = BoxContainer.ALIGNMENT_CENTER
	small_footer.add_theme_constant_override("separation", 16)
	offers_vbox.add_child(small_footer)

	small_reroll_btn = Button.new()
	small_reroll_btn.name = "SmallReroll"
	small_reroll_btn.text = "Reroll (0)"
	small_reroll_btn.custom_minimum_size = Vector2(140.0, 44.0)
	small_reroll_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_apply_flat_button_style(
		small_reroll_btn,
		Color(0.16, 0.22, 0.28),
		Color(0.36, 0.52, 0.66)
	)
	small_reroll_btn.pressed.connect(_on_reroll)
	small_footer.add_child(small_reroll_btn)

	small_cont_btn = Button.new()
	small_cont_btn.name = "SmallContinue"
	small_cont_btn.text = "Continue"
	small_cont_btn.custom_minimum_size = Vector2(140.0, 44.0)
	small_cont_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_apply_flat_button_style(
		small_cont_btn,
		Color(0.16, 0.22, 0.28),
		Color(0.36, 0.52, 0.66)
	)
	small_cont_btn.pressed.connect(_on_continue)
	small_footer.add_child(small_cont_btn)

	_refresh_reroll_button()

func _toggle_small_footer() -> void:
	if small_footer == null:
		_ensure_small_footer()
	if small_footer:
		small_footer.visible = true

func _hide_legacy_footer() -> void:
	if reroll_btn:
		reroll_btn.visible = false
	if cont_btn:
		cont_btn.visible = false

# -----------------------------------------------------------------------------
# Responsive reflow
# -----------------------------------------------------------------------------
func _on_resized() -> void:
	var vp_w: float = get_viewport_rect().size.x
	var content_w: float = maxf(0.0, vp_w - (EDGE_PADDING * 2.0))
	var gapf: float = float(GRID_GAP)
	var cols_fit: int = int(floorf((content_w + gapf) / (CARD_MIN_W + gapf)))
	var total_cards: int = SLOTS + 1
	var cols: int = clampi(cols_fit, 1, mini(6, total_cards))
	if offers_grid:
		offers_grid.columns = cols
	_update_card_sizes(cols)
	_toggle_small_footer()

func _update_card_sizes(cols: int) -> void:
	if offers_grid == null:
		return
	var vp_size: Vector2 = get_viewport_rect().size
	var avail_w: float = maxf(0.0, vp_size.x - (EDGE_PADDING * 2.0))
	var avail_h: float = maxf(0.0, vp_size.y - (EDGE_PADDING * 2.0))
	var padding: float = float(maxi(0, cols - 1)) * float(GRID_GAP)
	var usable_w: float = maxf(0.0, avail_w - padding)
	var card_w: float = clampf(usable_w / float(maxi(1, cols)), CARD_MIN_W, CARD_MAX_W)
	var card_h: float = clampf(avail_h * 0.48, CARD_MIN_H, CARD_MAX_H)
	for c in offers_grid.get_children():
		var card: PanelContainer = c as PanelContainer
		if card:
			card.custom_minimum_size = Vector2(card_w, card_h)

# -----------------------------------------------------------------------------
# UI / Flow
# -----------------------------------------------------------------------------
func _refresh_biscuits(_t: int = 0, _d: int = 0) -> void:
	if biscuits_l:
		biscuits_l.add_theme_font_size_override("font_size", 20)
		biscuits_l.text = "Biscuits: %d   Reroll: %d" % [
			GameState.biscuits, _effective_reroll_cost()
		]
	_refresh_card_buttons()
	_refresh_reroll_button()
	_refresh_stats_card()

func _on_upgrades_changed() -> void:
	_render_offers()

func _generate_if_needed() -> void:
	if _offers.size() == SLOTS:
		return
	_offers = _roll_offers(SLOTS)

# -----------------------------------------------------------------------------
# New-shop reseed preserving locked slots
# -----------------------------------------------------------------------------
func _reseed_unlocked_for_new_open(reset_reroll_cost: bool) -> void:
	if reset_reroll_cost:
		_reroll_cost = 2
	var keep: Dictionary = {}
	var exclude: Dictionary = {}
	var missing: int = 0
	for i in range(SLOTS):
		if i < _offers.size() and _slot_locked[i]:
			keep[i] = _offers[i]
			exclude[_offers[i]] = true
		else:
			missing += 1
	if _offers.size() != SLOTS:
		_offers.resize(SLOTS)
	if missing > 0:
		var new_picks: Array[String] = _roll_offers_excluding(missing, exclude)
		var j: int = 0
		for i in range(SLOTS):
			if keep.has(i):
				_offers[i] = String(keep[i])
			else:
				if j < new_picks.size():
					_offers[i] = new_picks[j]
					j += 1
	_render_offers()
	_refresh_biscuits()

# -----------------------------------------------------------------------------
# Offer rolling
# -----------------------------------------------------------------------------
func _roll_offers(n: int) -> Array[String]:
	var pool: Array[String] = []
	if DB and DB.is_ready():
		pool = DB.keys_sorted()
	else:
		pool = OFFER_KEYS.duplicate()
	if pool.is_empty():
		return []
	var weights: Array[float] = []
	weights.resize(pool.size())
	for i in pool.size():
		var key: String = pool[i]
		if not _is_entry_available(key):
			weights[i] = 0.0
			continue
		var def: Dictionary = {}
		if DB and DB.is_ready() and DB.has(key):
			def = DB.get_entry(key)
		weights[i] = _entry_weight(def)
	var picks: Array[String] = []
	var chosen: Dictionary = {}
	for _i in n:
		var idx: int = _weighted_pick(pool, weights, chosen)
		if idx < 0:
			break
		picks.append(pool[idx])
		chosen[idx] = true
	return picks

func _roll_offers_excluding(n: int, exclude: Dictionary) -> Array[String]:
	var pool: Array[String] = []
	if DB and DB.is_ready():
		pool = DB.keys_sorted()
	else:
		pool = OFFER_KEYS.duplicate()
	if pool.is_empty():
		return []
	var filt: Array[String] = []
	for k in pool:
		if exclude.has(k):
			continue
		filt.append(k)
	if filt.is_empty():
		return []
	var weights: Array[float] = []
	weights.resize(filt.size())
	for i in filt.size():
		var key: String = filt[i]
		if not _is_entry_available(key):
			weights[i] = 0.0
			continue
		var def: Dictionary = {}
		if DB and DB.is_ready() and DB.has(key):
			def = DB.get_entry(key)
		weights[i] = _entry_weight(def)
	var picks: Array[String] = []
	var chosen: Dictionary = {}
	for _i in n:
		var idx: int = _weighted_pick(filt, weights, chosen)
		if idx < 0:
			break
		picks.append(filt[idx])
		chosen[idx] = true
	return picks

func _entry_weight(def: Dictionary) -> float:
	var rarity: String = String(def.get("rarity", "common")).to_lower()
	var typ: String = String(def.get("type", "item")).to_lower()
	var base_r: float = float(BASE_RARITY_WEIGHTS.get(rarity, 0.1))
	var type_w: float = float(TYPE_WEIGHTS.get(typ, 1.0))
	var luck_norm: float = _get_player_luck_norm()
	var r_bonus: Vector2 = LUCK_RARITY_BONUS.get(rarity, Vector2.ZERO) as Vector2
	var mult: float = 1.0 + r_bonus.x * luck_norm
	mult = maxf(0.05, mult)
	return base_r * type_w * mult

func _weighted_pick(pool: Array[String], weights: Array[float], chosen: Dictionary) -> int:
	var total: float = 0.0
	for i in weights.size():
		if chosen.has(i):
			continue
		total += maxf(0.0, float(weights[i]))
	if total <= 0.0:
		for i in weights.size():
			if not chosen.has(i) and weights[i] > 0.0:
				return i
		return -1
	var r: float = _rng.randf() * total
	var acc: float = 0.0
	for i in weights.size():
		if chosen.has(i):
			continue
		var w: float = maxf(0.0, float(weights[i]))
		if w <= 0.0:
			continue
		acc += w
		if r <= acc:
			return i
	return -1

func _is_entry_available(key: String) -> bool:
	var def: Dictionary = {}
	if DB and DB.is_ready() and DB.has(key):
		def = DB.get_entry(key)
	var typ: String = String(def.get("type", "item"))
	var max_lvl: int = _get_max_level(key)
	var cur_lvl: int = GameState.get_item_count(key)
	if typ == "weapon" and cur_lvl >= 1:
		return false
	if cur_lvl >= max_lvl:
		return false
	return true

func _get_player_luck_norm() -> float:
	var luck_val: float = 0.0
	if GameState.has_method("get_stat"):
		luck_val = float(GameState.get_stat("luck"))
	elif GameState.has_method("get_all_stats"):
		var all: Dictionary = GameState.get_all_stats()
		if all.has("luck"):
			luck_val = float(all["luck"])
	return clampf(luck_val / 100.0, 0.0, 1.0)

# -----------------------------------------------------------------------------
# Render offers
# -----------------------------------------------------------------------------
func _render_offers() -> void:
	if offers_grid == null:
		return
	for n in offers_grid.get_children():
		(n as Node).queue_free()
	_card_ui.clear()
	_stats_card = null
	_stats_vbox = null
	_stats_label = null
	for i in range(SLOTS):
		if i >= _offers.size():
			break
		var key: String = _offers[i]
		var lvl: int = GameState.get_item_count(key)
		var max_lvl: int = _get_max_level(key)
		var card: PanelContainer = _make_card_container(_rarity_for(key))
		offers_grid.add_child(card)
		var vb: VBoxContainer = VBoxContainer.new()
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vb.add_theme_constant_override("separation", 6)
		card.add_child(vb)
		var name_label: Label = Label.new()
		name_label.text = _upgrade_title(key, lvl, max_lvl)
		name_label.add_theme_font_size_override("font_size", 22)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.custom_minimum_size.y = 32.0
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
		var lock_button: Button = Button.new()
		lock_button.toggle_mode = true
		lock_button.button_pressed = _slot_locked[i]
		lock_button.text = "Unlock" if _slot_locked[i] else "Lock"
		lock_button.custom_minimum_size = Vector2(0.0, 40.0)
		lock_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_apply_flat_button_style(
			lock_button,
			Color(0.13, 0.15, 0.18),
			Color(0.30, 0.34, 0.40)
		)
		lock_button.pressed.connect(_on_lock_toggled.bind(i, lock_button))
		buttons.add_child(lock_button)
		var buy_btn: Button = Button.new()
		buy_btn.custom_minimum_size = Vector2(0.0, 40.0)
		buy_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_apply_flat_button_style(
			buy_btn,
			Color(0.16, 0.22, 0.28),
			Color(0.36, 0.52, 0.66)
		)
		buy_btn.pressed.connect(_on_buy.bind(i))
		buttons.add_child(buy_btn)
		_card_ui.append({
			"index": i,
			"key": key,
			"name": name_label,
			"buy": buy_btn,
			"lock": lock_button
		})
	_add_stats_card()
	_refresh_card_buttons()
	_refresh_reroll_button()
	_refresh_stats_card()
	_on_resized()
	_toggle_small_footer()

# -----------------------------------------------------------------------------
# Card container
# -----------------------------------------------------------------------------
func _make_card_container(rarity: String = "common") -> PanelContainer:
	var card: PanelContainer = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = 0
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = _rarity_bg_color(rarity)
	sb.set_corner_radius_all(0)
	sb.set_border_width_all(1)
	sb.border_color = _rarity_border_color(rarity)
	sb.shadow_size = 0
	sb.set_content_margin_all(8.0)
	sb.content_margin_top = CARD_CONTENT_TOP
	card.add_theme_stylebox_override("panel", sb)
	return card

# -----------------------------------------------------------------------------
# Stats card
# -----------------------------------------------------------------------------
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
	name_label.custom_minimum_size.y = 32.0
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
			var k: Variant = keys[i]
			out_text += "[b]%s:[/b] %s" % [
				str(k).capitalize(), str(all[k])
			]
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

# -----------------------------------------------------------------------------
# Actions
# -----------------------------------------------------------------------------
func _on_lock_toggled(index: int, btn: Button) -> void:
	_slot_locked[index] = btn.button_pressed
	btn.text = "Unlock" if btn.button_pressed else "Lock"
	_refresh_card_buttons()
	_refresh_reroll_button()

func _on_buy(index: int) -> void:
	if index < 0 or index >= _offers.size():
		return
	var key: String = _offers[index]
	var lvl: int = GameState.get_item_count(key)
	var max_lvl: int = _get_max_level(key)
	if lvl >= max_lvl:
		return
	var cost: int = GameState.get_upgrade_cost(key)
	if not GameState.buy_entry(key, lvl):
		return
	var was_locked: bool = _slot_locked[index]
	if not was_locked:
		var replacement: Array[String] = _roll_offers_excluding(1, { _offers[index]: true })
		if replacement.size() > 0:
			_offers[index] = replacement[0]
	else:
		_slot_locked[index] = false
		var repl2: Array[String] = _roll_offers_excluding(1, {})
		if repl2.size() > 0:
			_offers[index] = repl2[0]
	_render_offers()
	_refresh_biscuits()

func _on_reroll() -> void:
	var cost: int = _effective_reroll_cost()
	if not GameState.spend_biscuits(cost):
		return
	var exclude: Dictionary = {}
	for i in range(SLOTS):
		if _slot_locked[i] and i < _offers.size():
			exclude[_offers[i]] = true
	for i in range(_offers.size()):
		if not _slot_locked[i]:
			var repl: Array[String] = _roll_offers_excluding(1, exclude)
			if repl.size() > 0:
				_offers[i] = repl[0]
				exclude[_offers[i]] = true
	_reroll_cost += 1
	_render_offers()
	_refresh_biscuits()

func _on_continue() -> void:
	emit_signal("continue_pressed")

# -----------------------------------------------------------------------------
# Text helpers
# -----------------------------------------------------------------------------
func _upgrade_title(key: String, lvl: int, max_lvl: int) -> String:
	var name: String = key.capitalize()
	if DB and DB.is_ready() and DB.has(key):
		var def: Dictionary = DB.get_entry(key)
		if not def.is_empty():
			name = String(def.get("name", name))
	return "%s  (Lv %d/%d)" % [name, lvl, max_lvl]

func _upgrade_desc(key: String) -> String:
	if DB and DB.is_ready() and DB.has(key):
		var def: Dictionary = DB.get_entry(key)
		if not def.is_empty():
			return String(def.get("desc", key))
	return key

func _get_max_level(key: String) -> int:
	if DB and DB.is_ready() and DB.has(key):
		var def: Dictionary = DB.get_entry(key)
		if not def.is_empty():
			var typ: String = String(def.get("type", "item"))
			if typ == "weapon":
				return 1
			var m: Variant = def.get("max_level")
			if typeof(m) != TYPE_NIL:
				return int(m)
	return 10

func _refresh_card_buttons() -> void:
	for ui in _card_ui:
		var idx: int = int(ui["index"])
		if idx < 0 or idx >= _offers.size():
			continue
		var key: String = _offers[idx]
		var lvl: int = GameState.get_item_count(key)
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
	if small_reroll_btn:
		small_reroll_btn.text = "Reroll (%d)" % _effective_reroll_cost()
		small_reroll_btn.disabled = GameState.biscuits < _effective_reroll_cost()

func _rarity_for(key: String) -> String:
	var def: Dictionary = {}
	if DB and DB.is_ready() and DB.has(key):
		def = DB.get_entry(key)
	return String(def.get("rarity", "common")).to_lower()

func _rarity_border_color(rarity: String) -> Color:
	match rarity:
		"legendary":
			return Color(0.95, 0.75, 0.20, 1.0)
		"rare":
			return Color(0.35, 0.60, 1.00, 1.0)
		"uncommon":
			return Color(0.35, 0.90, 0.55, 1.0)
		_:
			return Color(0.18, 0.22, 0.28, 1.0)

func _rarity_bg_color(rarity: String) -> Color:
	var base: Color = Color(0.06, 0.09, 0.12, 0.95)
	match rarity:
		"legendary":
			return base.lerp(Color(0.45, 0.33, 0.08, 0.95), 0.25)
		"rare":
			return base.lerp(Color(0.14, 0.22, 0.38, 0.95), 0.25)
		"uncommon":
			return base.lerp(Color(0.10, 0.22, 0.16, 0.95), 0.25)
		_:
			return base

func _effective_reroll_cost() -> int:
	var mult: float = 1.0
	if GameState and GameState.has_method("get_shop_price_mult"):
		mult = maxf(0.1, float(GameState.get_shop_price_mult()))
	return maxi(1, int(round(mult * float(_reroll_cost))))

# -----------------------------------------------------------------------------
# Button styling helper
# -----------------------------------------------------------------------------
func _apply_flat_button_style(btn: Button, base_bg: Color, base_border: Color) -> void:
	var normal: StyleBoxFlat = StyleBoxFlat.new()
	normal.set_corner_radius_all(0)
	normal.set_border_width_all(1)
	normal.bg_color = base_bg
	normal.border_color = base_border
	normal.set_content_margin_all(6.0)

	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = Color(
		minf(1.0, base_bg.r + 0.04),
		minf(1.0, base_bg.g + 0.04),
		minf(1.0, base_bg.b + 0.04),
		base_bg.a
	)

	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = Color(
		maxf(0.0, base_bg.r - 0.04),
		maxf(0.0, base_bg.g - 0.04),
		maxf(0.0, base_bg.b - 0.04),
		base_bg.a
	)

	var disabled: StyleBoxFlat = normal.duplicate()
	disabled.bg_color = Color(base_bg.r, base_bg.g, base_bg.b, 0.6)
	disabled.border_color = Color(base_border.r, base_border.g, base_border.b, 0.8)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("disabled", disabled)
	btn.add_theme_stylebox_override("focus", hover)
