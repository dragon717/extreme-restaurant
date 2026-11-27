extends VBoxContainer

const Style = preload("res://scripts/ui/style.gd")
const Icon = preload("res://scripts/ui/ui_icon.gd")
const Actor = preload("res://scripts/visuals/actor_view.gd")
const STAGES = [["door", "到店"], ["recipe", "点单"], ["clock", "等餐"], ["table", "用餐"], ["check", "离店"]]
const PHASES = {
	"APPROACHING": [0, "走向店门"], "QUEUE": [0, "排队等位"], "SEATING": [0, "前往座位"],
	"CHOOSING": [1, "挑选菜品"], "READY": [1, "等待点单"], "TAKING": [1, "正在点单"],
	"FOOD": [2, "等待上菜"], "EATING": [3, "正在用餐"], "STAYING": [3, "等同桌"],
	"LEAVING": [4, "离店"], "AT_EXIT": [4, "等同伴会合"], "EXITING": [4, "离店"],
	"REFUSING": [4, "缺匹配餐桌"], "GONE": [4, "已离店"]
}

var hero: PanelContainer
var avatar
var category: Label
var phase_label: Label
var dish: Label
var stage_items: Array[Dictionary] = []
var meter_panel: PanelContainer
var meter_title: Label
var meter_value: Label
var meter: ProgressBar
var trait_label: Label
var guest_id := -1
var last_state := ""
var meter_animation: Tween
var phase_animation: Tween
var entry_animation: Tween
var target := -1.0

func _ready() -> void:
	add_theme_constant_override("separation", 10)
	hero = Style.card()
	add_child(hero)
	var glance = HBoxContainer.new()
	hero.add_child(glance)
	var portrait = Control.new()
	portrait.custom_minimum_size = Vector2(60, 63)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glance.add_child(portrait)
	avatar = Actor.new()
	avatar.position = Vector2(30, 36)
	avatar.z_index = 1
	avatar.set_display_zoom(1.25)
	portrait.add_child(avatar)
	var text = VBoxContainer.new()
	text.add_theme_constant_override("separation", 3)
	glance.add_child(text)
	category = Style.text("", 12, Style.MUTED)
	text.add_child(category)
	phase_label = Style.text("", 19)
	phase_label.name = "GuestActivity"
	text.add_child(phase_label)
	dish = Style.text("", 13, Style.MUTED)
	dish.name = "GuestDish"
	text.add_child(dish)

	var path = HBoxContainer.new()
	path.add_theme_constant_override("separation", 4)
	add_child(path)
	for datum in STAGES:
		var chip = Style.card()
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		path.add_child(chip)
		var stack = VBoxContainer.new()
		stack.add_theme_constant_override("separation", 4)
		chip.add_child(stack)
		var icon = Icon.make(datum[0], Style.MUTED, 17)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		stack.add_child(icon)
		var caption = Style.text(datum[1], 12, Style.MUTED)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stack.add_child(caption)
		stage_items.append({"chip": chip, "icon": icon, "caption": caption})

	meter_panel = Style.card()
	meter_panel.add_theme_stylebox_override("panel", Style.box(Style.BG, Color("476160"), 8, 9))
	add_child(meter_panel)
	var meter_stack = VBoxContainer.new()
	meter_stack.add_theme_constant_override("separation", 5)
	meter_panel.add_child(meter_stack)
	var header = HBoxContainer.new()
	meter_stack.add_child(header)
	meter_title = Style.text("", 13, Style.MUTED)
	meter_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(meter_title)
	meter_value = Style.text("", 13)
	header.add_child(meter_value)
	meter = ProgressBar.new()
	meter.name = "GuestProgress"
	meter.custom_minimum_size.y = 7
	meter.show_percentage = false
	meter.max_value = 1.0
	meter.step = .001
	meter_stack.add_child(meter)
	trait_label = Style.text("", 13, Style.MUTED, true)
	trait_label.name = "GuestTraits"
	add_child(trait_label)

func present(sim, customer: Dictionary, traits: String, reveal := false) -> void:
	var id = int(customer.id)
	var state = str(customer.state)
	var info = PHASES.get(state, [0, tr("在餐厅")])
	var changed = id != guest_id or state != last_state
	var def = sim.guest_defs[customer.type]
	var accent = Style.RED if def.rarity == "special" else (Style.GOLD if def.rarity == "rare" else Style.GREEN)
	if changed or reveal:
		hero.add_theme_stylebox_override("panel", Style.box(Color("192f34"), accent.darkened(.5), 10, 8))
		phase_label.text = tr(str(info[1]))
		phase_label.add_theme_color_override("font_color", accent)
		var caption = {"normal": tr("日常客人"), "rare": tr("稀有客人"), "special": tr("特殊来客")}[def.rarity]
		if int(customer.party_size) > 1:
			caption += tr(" · %d 人同行") % int(customer.party_size)
		category.text = caption
		avatar.set_visual(str(customer.type))
		var pose = "eat" if state == "EATING" else ("walk" if int(info[0]) == 0 or int(info[0]) == 4 else "idle")
		avatar.present(pose)
		_update_stages(int(info[0]), accent)
		if is_instance_valid(phase_animation) and phase_animation.is_valid(): phase_animation.kill()
		phase_label.modulate.a = .5
		phase_animation = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		phase_animation.tween_property(phase_label, "modulate:a", 1.0, .26)
	guest_id = id
	last_state = state
	dish.text = tr("尚未选菜") if str(customer.recipe).is_empty() else tr("所点菜 · ") + tr(str(sim.recipes[customer.recipe].name))
	trait_label.text = traits
	trait_label.visible = not traits.is_empty()
	_update_meter(sim, customer, changed or reveal)
	if reveal:
		if is_instance_valid(entry_animation) and entry_animation.is_valid(): entry_animation.kill()
		modulate.a = .35
		entry_animation = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		entry_animation.tween_property(self, "modulate:a", 1.0, .27)

func _update_stages(phase: int, accent: Color) -> void:
	for i in range(stage_items.size()):
		var item = stage_items[i]
		var tint = accent if i == phase else (Style.GREEN.darkened(.1) if i < phase else Style.MUTED.darkened(.24))
		item.chip.add_theme_stylebox_override("panel", Style.box(Color("314847") if i == phase else Style.BG, tint.darkened(.45), 6, 5))
		item.icon.set_glyph(STAGES[i][0], tint)
		item.caption.add_theme_color_override("font_color", tint)

func _update_meter(sim, customer: Dictionary, reset: bool) -> void:
	var seconds = float(sim.tick_ms) / 1000.0
	var progress := -1.0
	var tint = Style.GREEN
	match str(customer.state):
		"QUEUE":
			meter_title.text = tr("已排队")
			meter_value.text = tr("%.1f 秒") % (float(sim.tick - int(customer.arrival_tick)) * seconds)
		"FOOD":
			var unlimited = bool(sim.guest_defs[customer.type].get("unlimited_food_wait", false))
			var end = int(customer.next_penalty if unlimited else customer.food_max)
			meter_title.text = tr("距下次扣声望") if unlimited else tr("剩余等餐耐心")
			meter_value.text = tr("%.1f 秒") % (maxi(0, end - sim.tick) * seconds)
			var duration = sim._guest_seconds(customer, "cycle" if unlimited else "food_max")
			progress = clampf(float(end - sim.tick) * seconds / maxf(seconds, duration), 0, 1)
			tint = Style.RED if progress < .28 or unlimited else Style.GOLD
		"EATING":
			var duration = sim._guest_seconds(customer, "eat")
			var remaining = maxi(0, int(customer.deadline) - sim.tick) * seconds
			progress = clampf(1.0 - remaining / maxf(seconds, duration), 0, 1)
			meter_title.text = tr("用餐进度")
			meter_value.text = tr("剩 %.1f 秒") % remaining
		"STAYING":
			meter_title.text = tr("已完成用餐")
			meter_value.text = tr("等同桌客人")
			progress = 1.0
	meter_panel.visible = progress >= 0.0 or customer.state == "QUEUE"
	meter.visible = progress >= 0.0
	if progress < 0.0:
		target = -1.0
		return
	if reset or not is_equal_approx(progress, target):
		target = progress
		if is_instance_valid(meter_animation) and meter_animation.is_valid(): meter_animation.kill()
		if reset: meter.value = .0 if customer.state == "EATING" else 1.0
		meter_animation = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		meter_animation.tween_property(meter, "value", progress, .19)
	meter.add_theme_stylebox_override("fill", Style.box(tint, tint, 3, 0))
