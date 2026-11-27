extends VBoxContainer

const Style = preload("res://scripts/ui/style.gd")
const Icon = preload("res://scripts/ui/ui_icon.gd")
const THEMES = {
	"food_festival": ["crowd", Color("f1c082")],
	"thug_visit": ["alert", Color("f2a392")],
	"group_booking": ["table", Color("a9d6b8")],
	"food_inspection": ["check", Color("c2d0f4")],
	"bad_weather": ["clock", Color("a6c7db")],
	"food_review": ["star", Color("f6d79d")],
	"river_lantern_run": ["star", Color("f7cd8b")],
}

signal confirmed

func populate(event: Dictionary, challenge: Dictionary, viewed: bool, guest: Dictionary) -> void:
	var motif = THEMES.get(event.id, ["alert", Style.GOLD])
	var accent: Color = motif[1]
	%Poster.add_theme_stylebox_override("panel", Style.frame(Color("17272d"), accent.darkened(.51), 12))
	var cover: VBoxContainer = %Cover
	_add_art(cover, event)
	var date = tr("第 %d 天") % int(event.from_day) if event.from_day == event.to_day else tr("第 %d–%d 天") % [int(event.from_day), int(event.to_day)]
	Style.readout(cover, "clock", date, tr("事件生效日期"), accent, 16)
	var story = Style.text(str(event.description), 16, Style.INK, true)
	cover.add_child(story)
	var detail: VBoxContainer = %Details
	var effects = _section(detail, tr("营业影响"), motif[0], accent)
	for line in effect_lines(event, guest):
		var paragraph = Style.text(line, 15, Style.INK, true)
		effects.add_child(paragraph)
	if not challenge.is_empty():
		var goal = _section(detail, tr("限时任务"), "star", Style.GOLD)
		goal.add_child(Style.text(tr("每天各获 %d 闪星 · 奖励 %s") % [int(challenge.required), reward_text(challenge.reward)], 14, Style.MUTED, true))
		var stamps = HBoxContainer.new()
		stamps.add_theme_constant_override("separation", 6)
		goal.add_child(stamps)
		for entry in challenge.days:
			var earned = int(entry.stars)
			var tint = Style.GOLD if earned >= int(challenge.required) else Style.MUTED
			var stamp = Style.card()
			stamp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			stamp.add_theme_stylebox_override("panel", Style.box(Color("263c3d"), tint.darkened(.48), 8, 6))
			stamps.add_child(stamp)
			var column = VBoxContainer.new()
			column.add_theme_constant_override("separation", 3)
			stamp.add_child(column)
			var date_label = Style.text(tr("第 %d 天") % int(entry.day), 12, tint)
			date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			column.add_child(date_label)
			var pips = HBoxContainer.new()
			pips.alignment = BoxContainer.ALIGNMENT_CENTER
			pips.add_theme_constant_override("separation", 3)
			column.add_child(pips)
			for i in range(int(challenge.required)):
				pips.add_child(Icon.make("star" if i < earned else "star_outline", tint, 12))
	var grant = event.notice.get("grant", {})
	var confirm: Button = %ConfirmMajorEvent
	confirm.text = tr("确定并领取 ") + reward_text(grant) if not viewed and not grant.is_empty() else tr("确定")
	Style.accent_button(confirm)
	confirm.pressed.connect(confirmed.emit)
	detail.modulate.a = .3
	detail.create_tween().tween_property(detail, "modulate:a", 1.0, .30).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _section(parent: VBoxContainer, title: String, glyph: String, accent: Color) -> VBoxContainer:
	var card = Style.card()
	card.add_theme_stylebox_override("panel", Style.frame(Color("1b2d33"), accent.darkened(.52), 12))
	parent.add_child(card)
	var stack = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 7)
	card.add_child(stack)
	Style.readout(stack, glyph, title, "", accent, 16)
	return stack

func _add_art(parent: VBoxContainer, event: Dictionary) -> void:
	var path = str(event.notice.get("art", ""))
	if path.is_empty(): return
	var art = TextureRect.new()
	art.name = "MajorEventArtwork"
	art.custom_minimum_size.y = 216
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(path):
		art.texture = load(path) as Texture2D
	else:
		var raster = Image.load_from_file(path)
		if raster != null and not raster.is_empty(): art.texture = ImageTexture.create_from_image(raster)
	parent.add_child(art)

static func reward_text(reward: Dictionary) -> String:
	var parts = []
	if reward.has("reputation"): parts.append(TranslationServer.translate("%d 声望") % int(reward.reputation))
	if reward.has("gold"): parts.append(TranslationServer.translate("%d 金币") % int(reward.gold))
	return TranslationServer.translate("和").join(parts)

static func peak_time(peak: Dictionary) -> String:
	var start = int(peak.start_minute)
	var end = int(peak.end_minute)
	@warning_ignore("integer_division")
	return "%02d:%02d–%02d:%02d" % [start / 60, start % 60, end / 60, end % 60]

static func effect_lines(event: Dictionary, guest: Dictionary) -> Array:
	var lines = []
	var traffic = event.get("traffic", {})
	var names = {"normal":TranslationServer.translate("普通客人"),"rare":TranslationServer.translate("稀有客人"),"2":TranslationServer.translate("双人组"),"4":TranslationServer.translate("四人组")}
	var counts = []
	for category in names:
		if not traffic.has(category): continue
		var pct = roundi(float(traffic[category]) * 100.0)
		counts.append("%s %s%d%%" % [names[category], "+" if pct > 0 else "", pct])
	if not counts.is_empty(): lines.append(TranslationServer.translate("每天  ") + " · ".join(counts))
	if event.has("regular_traffic_multiplier"):
		lines.append(TranslationServer.translate("每天的常规客流减少 %d%%") % roundi((1.0 - float(event.regular_traffic_multiplier)) * 100))
	if not guest.is_empty():
		if guest.get("unlimited_food_wait", false):
			lines.append(TranslationServer.translate("第 %d 天来一人，第 %d 天来两人。记得留出双人桌。") % [int(event.from_day), int(event.to_day)])
			lines.append(TranslationServer.translate("地痞会一直等到上菜，每人每轮等餐扣 %d 声望。") % int(guest.food_penalty_per_cycle))
		elif event.has("quality_inspection"):
			var config = event.quality_inspection
			lines.append(TranslationServer.translate("%d 位安全员同桌用餐，用餐时长为平时的 %d 倍。") % [int(event.special_visits[0].size), int(guest.eat_time_multiplier)])
			var base = roundi((1.0 - float(config.neutral_quality)) * 100.0 * int(config.reputation_per_percentage_point))
			lines.append(TranslationServer.translate("全组餐点平均品质 %d%% 时声望持平。100%% 品质扣 %d 声望，超出标准有奖励。") % [roundi(float(config.neutral_quality) * 100), -base])
			lines.append(TranslationServer.translate("未上齐的餐点会拉低检查结果。"))
		else:
			lines.append(TranslationServer.translate("会有一位%s到店。") % TranslationServer.translate(str(guest.name)))
	if event.has("arrival_peak"): lines.append(TranslationServer.translate("%s 集中约 %d%% 的计划客流") % [peak_time(event.arrival_peak), roundi(float(event.arrival_peak.share) * 100.0)])
	if event.has("quality_expectation_add"): lines.append(TranslationServer.translate("客人品质要求 +%d 个百分点") % roundi(float(event.quality_expectation_add) * 100.0))
	if event.has("payment_pct"): lines.append(TranslationServer.translate("菜价收益 +%d%%") % roundi(float(event.payment_pct) * 100.0))
	return lines
