extends PanelContainer

signal item_picked(id: String)
signal closed

const Style = preload("res://scripts/ui/style.gd")
const Icon = preload("res://scripts/ui/ui_icon.gd")
const Grid = preload("res://scripts/core/layout.gd")
const HEIGHT := 226.0
const CATEGORIES = {"all": ["build", "全部"], "table": ["table", "餐桌"],
	"stove": ["stove", "厨房"], "trophy": ["trophy", "奖杯"], "wall": ["wall", "隔墙"], "decoration": ["star_outline", "装饰"]}

var sim
var active_category := "all"
var category_buttons := {}
var tiles := {}
var inventory_revision := -1
var search := LineEdit.new()
var scroll := ScrollContainer.new()
var items := GridContainer.new()
var empty: Label
var instruction: Label
var selection := ""

func _ready() -> void:
	add_theme_stylebox_override("panel", Style.surface(Style.GOLD, 12))
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	add_child(stack)
	var header := HBoxContainer.new()
	stack.add_child(header)
	header.add_child(Icon.make("build", Style.GOLD, 22))
	header.add_child(Style.text(tr("建造"), 21, Style.GOLD))
	instruction = Style.text("", 14, Style.MUTED)
	instruction.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	instruction.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header.add_child(instruction)
	search.placeholder_text = tr("搜索物件")
	search.clear_button_enabled = true
	search.custom_minimum_size.x = 168
	search.text_changed.connect(func(_query): _populate())
	header.add_child(search)
	var close = Style.button("")
	close.tooltip_text = tr("关闭建造 [Esc]")
	close.accessibility_name = tr("关闭建造")
	close.custom_minimum_size.x = 38
	Icon.center_in(close, "close", Style.INK, 17)
	close.pressed.connect(closed.emit)
	header.add_child(close)
	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 13)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(content)
	var categories := GridContainer.new()
	categories.columns = 2
	categories.add_theme_constant_override("h_separation", 5)
	categories.add_theme_constant_override("v_separation", 5)
	content.add_child(categories)
	for key in CATEGORIES:
		var button = Style.button("")
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(76, 44)
		button.tooltip_text = CATEGORIES[key][1]
		button.accessibility_name = button.tooltip_text
		var caption = Style.text(CATEGORIES[key][1], 13)
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 4)
		var center := CenterContainer.new()
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(center)
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		center.add_child(row)
		row.add_child(Icon.make(CATEGORIES[key][0], Style.GREEN, 19))
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(caption)
		button.pressed.connect(_select_category.bind(key))
		categories.add_child(button)
		category_buttons[key] = button
	var tray := PanelContainer.new()
	tray.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tray.add_theme_stylebox_override("panel", Style.inset(7,6))
	content.add_child(tray)
	tray.add_child(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.resized.connect(_resize_grid)
	var holder := VBoxContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(holder)
	items.add_theme_constant_override("h_separation", 7)
	items.add_theme_constant_override("v_separation", 7)
	holder.add_child(items)
	empty = Style.text("", 15, Style.MUTED, true)
	holder.add_child(empty)
	_select_category(active_category)

func refresh(simulation, current: String, status: String) -> void:
	instruction.text = status
	selection = current
	if sim != simulation or inventory_revision != simulation.revision:
		sim = simulation
		inventory_revision = sim.revision
		_populate()
	else:
		_sync_selected()

func _select_category(category: String) -> void:
	active_category = category
	for key in category_buttons:
		category_buttons[key].set_pressed_no_signal(key == category)
	scroll.scroll_vertical = 0
	_populate()

func _resize_grid() -> void:
	items.columns = maxi(1, floori((scroll.size.x - 14) / 127))

func _populate() -> void:
	for child in items.get_children():
		items.remove_child(child)
		child.queue_free()
	tiles.clear()
	if sim == null: return
	category_buttons.decoration.visible = sim.decoration_shop_unlocked()
	if active_category == "decoration" and not category_buttons.decoration.visible:
		_select_category("all")
		return
	var query = search.text.strip_edges().to_lower()
	var inventory = sim.stored_facilities(active_category if active_category != "all" else "")
	for item in inventory:
		if not CATEGORIES.has(item.type) or item.type == "wall": continue
		var caption := Style.facility_name(str(item.name))
		if not query.is_empty() and not caption.to_lower().contains(query) and not str(item.name).to_lower().contains(query): continue
		var detail = tr("%d 座") % Grid.table_size(item) if item.type == "table" else ""
		var card = _tile(item.id, caption, item.type, detail, Grid.table_size(item), item.get("relic_id", ""))
		if item.type == "decoration":
			var thumb = card.get_child(0).get_child(0)
			thumb.decoration = sim.decoration_defs[item.decoration_id]
			card.tooltip_text = caption + " · " + preload("res://scripts/core/decoration_effects.gd").description(thumb.decoration)
		if item.type == "trophy" and Grid.facilities(sim.layout, "trophy").size() >= int(sim.attributes.relic_slots):
			card.disabled = true
			card.tooltip_text = tr("展示位已满，先收起一件奖杯")
	if active_category in ["all", "wall"] and (query.is_empty() or tr("木纹隔墙").to_lower().contains(query)):
		_tile("@wall", tr("木纹隔墙"), "wall", tr("免费"), 1)
	empty.visible = tiles.is_empty()
	empty.text = tr("没有找到物件") if not query.is_empty() else tr("背包里还没有此类物件。选中场景里的设施，可用右下角的收起工具。")
	_sync_selected()

func _tile(id: String, caption: String, kind: String, detail: String, seats: int, relic_id := "") -> Button:
	var btn = Style.button("")
	Style.quiet_button(btn)
	btn.toggle_mode = true
	btn.name = "BuildWall" if id == "@wall" else "Build_" + id
	btn.accessibility_name = caption
	btn.tooltip_text = caption + tr(" · 选中后在场景放置")
	btn.custom_minimum_size = Vector2(120, 116)
	items.add_child(btn)
	tiles[id] = btn
	var body := VBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("separation", 2)
	btn.add_child(body)
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.offset_left = 6
	body.offset_right = -6
	body.offset_top = 5
	body.offset_bottom = -4
	var thumb := Thumbnail.new()
	thumb.kind = kind
	thumb.seats = seats
	if kind == "trophy": thumb.metal = Color(str(sim.relic_defs[relic_id].color))
	thumb.custom_minimum_size.y = 63
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(thumb)
	var title = Style.text(caption, 14)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(title)
	if not detail.is_empty():
		var meta = Style.text(detail, 12, Style.GOLD)
		meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(meta)
	btn.pressed.connect(item_picked.emit.bind(id))
	return btn

func _sync_selected() -> void:
	for id in tiles:
		tiles[id].set_pressed_no_signal(id == selection)

class Thumbnail extends Control:
	const Style = preload("res://scripts/ui/style.gd")
	var kind := ""
	var seats := 1
	var metal := Color("ebc185")
	var decoration := {}

	func _draw_decoration() -> void:
		var art = preload("res://scripts/visuals/decoration_art.gd")
		art.paint(self, Rect2(size * .5 - Vector2(25, 24), Vector2(50, 46)), decoration)

	func _draw() -> void:
		if kind == "decoration" and not decoration.is_empty():
			_draw_decoration()
			return
		draw_set_transform(size * Vector2(.5, .48))
		draw_circle(Vector2(0, 9), 24, Color("183338", .65))
		match kind:
			"table":
				var wide = 20 if seats == 1 else 30
				draw_rect(Rect2(-wide, -14, wide * 2, 29), Color("866246"))
				draw_rect(Rect2(-wide, -19, wide * 2, 27), Color("ccab78"))
				draw_rect(Rect2(-wide + 5, -15, wide * 2 - 10, 17), Color("ead3aa"))
				draw_rect(Rect2(-4, -18, 8, 23), Color("65958b"))
				for i in range(seats):
					var x = -wide + (i + .5) * (wide * 2.0 / seats)
					draw_rect(Rect2(x - 4, 16, 8, 6), Color("b6855b"))
			"stove":
				draw_rect(Rect2(-25, -19, 50, 38), Color("a8bdac"))
				draw_rect(Rect2(-25, 13, 50, 9), Color("3e5954"))
				for point in [Vector2(-11,-10), Vector2(11,-10), Vector2(-11,5), Vector2(11,5)]:
					draw_circle(point, 6, Color("4b5f59"))
					draw_circle(point, 3, Color("d8b783"))
			"trophy":
				draw_rect(Rect2(-18, 15, 36, 7), Color("a07651"))
				draw_circle(Vector2(0,-5), 14, metal)
				draw_circle(Vector2(0,-6), 9, metal.darkened(.35))
				draw_circle(Vector2(-2,-8), 4, metal.lightened(.45))
				draw_rect(Rect2(-3, 6, 6, 10), metal)
			"wall":
				draw_rect(Rect2(-27,-16,54,36), Color("765940"))
				for x in range(-25,26,10):
					draw_rect(Rect2(x,-17,8,34), Color("bc9569"))
					draw_line(Vector2(x+2,-12), Vector2(x+2,13), Color("9c7752"), 1)
				draw_rect(Rect2(-28,-19,56,5), Color("e0bd8d"))

