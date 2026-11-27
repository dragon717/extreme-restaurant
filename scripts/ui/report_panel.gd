extends VBoxContainer

signal locate_requested
signal continue_requested
signal restart_requested
signal return_requested
signal history_requested

const Style = preload("res://scripts/ui/style.gd")
const MajorEventPanel = preload("res://scripts/ui/major_event_panel.gd")
const Charts = preload("res://scripts/ui/report_charts.gd")
const Bubble = preload("res://scripts/ui/speech_bubble.gd")
const DIAGNOSTIC_TEXT = {
	"ordering": {"label": "待点单", "hint": "查看等待最久的桌位，检查它们与服务员往返订单口的路线。", "facilities": ["order"]},
	"kitchen": {"label": "到出餐口前", "hint": "等餐主要发生在餐品到达出餐口之前。先看送单、灶台和厨师搬运。", "facilities": ["order", "pass"]},
	"delivery": {"label": "出餐口到客桌", "hint": "等餐主要发生在餐品到达出餐口之后。先看取餐和送到客桌的路线。", "facilities": ["pass"]},
	"queue": {"label": "排队未入座率", "hint": "这批客人未能入座。查看入口队列，检查餐桌是否周转得过来。", "facilities": []}
}

const CARD_BORDER = Color("4c6567")
const NO_SAMPLE = "—"

var earned_goals: Array[Control] = []

func populate(report: Dictionary, previous: Dictionary, catalog: Dictionary, notices: Array[String], guide_line := "", archive := false) -> void:
	var totals: HBoxContainer = %Totals
	_total(totals, "coins", tr("收摊金币") if archive else tr("持有金币"), "%d$" % int(report.gold_after), "+%d$" % int(report.income), tr("今日营收"), Style.GOLD)
	var daily_rep = int(report.get("reputation_change", int(report.rep_base) + int(report.rep_buff) - int(report.wait_penalty_actual) - int(report.quality_penalty_actual)))
	_total(totals, "reputation", tr("收摊声望") if archive else tr("当前声望"), str(int(report.reputation_after)), "%+d" % daily_rep, tr("今日声望变化"), Style.GREEN)
	_total(totals, "star", tr("闪星余额"), str(int(report.stars_after)), "+%d" % int(report.stars_earned), tr("今日获得闪星"), Style.GOLD)
	var goals: HBoxContainer = %Goals
	_add_goal(goals, tr("零拒客"), tr("所有计划到店者均进入餐厅"), report.star_goals[0])
	_add_goal(goals, tr("无等餐扣分"), tr("没有等餐扣分或超时"), report.star_goals[1])
	_add_goal(goals, tr("午夜前完餐 %d/%d · ≥%d%%") % [report.get("completed_before_midnight", report.completed), report.planned, report.completion_target],
		tr("午夜前至少 %d 人完餐") % int(report.completion_required), report.star_goals[2])
	for goal in report.get("major_event_goals", []):
		var progress = tr("%s挑战 · %d/%d 天达成") % [tr(str(goal.name)), int(goal.passed), goal.days.size()]
		if goal.finished:
			progress += tr(" · 获得 ") + MajorEventPanel.reward_text(goal.reward) if goal.success else tr(" · 已结束")
		Style.readout(%Announcements, "star" if goal.success else "star_outline", progress, tr("重大事件限时任务"), Style.GOLD, 15)
	if report.has("quality_inspection"):
		var result = report.quality_inspection
		var result_text = tr("品质 %.0f%% · 声望 %+d") % [float(result.quality) * 100, int(result.change)]
		if int(result.served) < int(result.expected):
			result_text = tr("上餐 %d/%d · 声望 %+d") % [int(result.served), int(result.expected), int(result.change)]
		if int(result.change) != int(result.assessed):
			result_text += tr("（评定 %+d）") % int(result.assessed)
		var color = Style.RED if int(result.assessed) < 0 else (Style.GREEN if int(result.assessed) > 0 else Style.MUTED)
		var inspection_line = Style.readout(%Announcements, "alert", tr("食品安全检查 · ") + result_text, tr("评定声望 %+d") % int(result.assessed), color, 15)
		inspection_line.mouse_filter = Control.MOUSE_FILTER_PASS
	_add_report_views(report, previous, catalog, notices, guide_line, archive)
	if int(report.rent_amount) > 0:
		var shortfall = int(report.rent_amount) - int(report.gold_after)
		var status = tr("已缴清") if report.rent_ok else tr("还差 %d$，章节结束") % shortfall
		%Rent.text = tr("周租 %d$ · %s") % [report.rent_amount, status]
		%Rent.add_theme_color_override("font_color", Style.MUTED if report.rent_ok else Style.RED)
		%Rent.show()
	%Announcements.visible = %Announcements.get_child_count() > 0
	%Actions.visible = not archive
	if archive: return
	%History.pressed.connect(history_requested.emit)
	var button: Button = %Primary
	button.text = tr("进入第 %d 天夜晚") % (report.day + 1) if report.result == "CONTINUE" else (tr("返回章节") if report.result == "WIN" else tr("重新挑战本章"))
	Style.accent_button(button)
	if report.result == "CONTINUE":
		button.pressed.connect(continue_requested.emit)
	else:
		button.pressed.connect(return_requested.emit if report.result == "WIN" else restart_requested.emit)
		var secondary: Button = %Secondary
		secondary.text = tr("重新挑战") if report.result == "WIN" else tr("返回章节")
		secondary.pressed.connect(restart_requested.emit if report.result == "WIN" else return_requested.emit)
		secondary.show()
	button.grab_focus()

func _total(row: HBoxContainer, glyph: String, caption: String, value: String, delta: String, detail: String, tint: Color) -> void:
	var card = Style.card()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", Style.inset(12,8))
	row.add_child(card)
	var stack = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 2)
	card.add_child(stack)
	stack.add_child(Style.text(caption, 13, Style.MUTED))
	var amounts = HBoxContainer.new()
	stack.add_child(amounts)
	var balance = Style.readout(amounts, glyph, value, caption, tint, 27)
	balance.name = glyph + "_balance"
	var change_tint = Style.MUTED
	if delta.to_int() != 0:
		change_tint = Style.RED if delta.begins_with("-") else Style.GREEN
	var change = Style.text("(" + delta + ")", 15, change_tint)
	change.name = glyph + "_daily_change"
	change.tooltip_text = detail
	change.accessibility_name = detail + " " + delta
	amounts.add_child(change)

func _add_goal(row: HBoxContainer, caption: String, description: String, earned: bool) -> void:
	var chip = Style.card()
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip.add_theme_stylebox_override("panel", Style.inset(8,5))
	chip.tooltip_text = description
	row.add_child(chip)
	var label := Style.readout(chip, "star" if earned else "star_outline", caption, description, Style.GOLD if earned else Style.MUTED, 14)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if earned: earned_goals.append(chip)

func reveal_earned_goals() -> void:
	for i in range(earned_goals.size()):
		var chip = earned_goals[i]
		chip.modulate.a = .64
		var glow = chip.create_tween()
		glow.tween_interval(.21 + .10 * i)
		glow.tween_callback(_animate_goal.bind(chip))
		glow.tween_property(chip, "modulate", Color(1.13, 1.09, .88), .12).set_ease(Tween.EASE_OUT)
		glow.tween_property(chip, "modulate", Color.WHITE, .22)

func _animate_goal(chip: Control) -> void:
	if DisplayServer.get_name() == "headless": return
	var burst := Style.REVEAL.instantiate() as Node2D
	chip.add_child(burst)
	burst.position = Vector2(19, chip.size.y * .5)
	burst.scale = Vector2.ONE * .64

func _add_report_views(report: Dictionary, previous: Dictionary, catalog: Dictionary, notices: Array[String], guide_line: String, archive: bool) -> void:
	var views: TabContainer = %ReportViews
	views.add_theme_stylebox_override("panel", Style.inset(10,8))
	var tab_colors = {
		"tab_selected": [Style.PANEL, Style.GOLD],
		"tab_unselected": [Style.BG, CARD_BORDER],
		"tab_hovered": [Style.PANEL_LIGHT, Style.GREEN],
	}
	for state in tab_colors:
		var colors = tab_colors[state]
		var tab_style = Style.box(colors[0], colors[1], 7, 8)
		tab_style.content_margin_left = 18
		tab_style.content_margin_right = 18
		views.add_theme_stylebox_override(state, tab_style)
	views.add_theme_color_override("font_selected_color", Style.GOLD)
	views.add_theme_color_override("font_unselected_color", Style.MUTED)

	var overview = VBoxContainer.new()
	overview.name = "总览"
	views.add_child(overview)
	views.set_tab_title(0, tr(overview.name))
	var columns = HBoxContainer.new()
	overview.add_child(columns)
	var outcomes = _data_card(columns)
	_add_heading(outcomes, tr("到店结果"))
	_add_guest_outcomes(outcomes, report)
	var metrics = _data_card(columns)
	_add_key_metrics(metrics, report, previous)
	if not archive: _add_focus(overview, report)
	if not notices.is_empty():
		var forecast = _data_card(overview)
		var row = HBoxContainer.new()
		forecast.add_child(row)
		row.add_child(Style.text(tr("明日预告"), 15, Style.GOLD))
		var items = Style.text("    ·    ".join(notices), 14, Style.INK, true)
		items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(items)

	var scroller = ScrollContainer.new()
	scroller.name = "明细"
	scroller.custom_minimum_size.y = maxf(300, overview.get_combined_minimum_size().y)
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	views.add_child(scroller)
	views.set_tab_title(1, tr(scroller.name))
	var details = VBoxContainer.new()
	details.name = "ReportDetails"
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroller.add_child(details)
	_add_details(details, report, previous, catalog)
	if not guide_line.is_empty():
		var guide = VBoxContainer.new()
		guide.name = "阿禾手记"
		views.add_child(guide)
		views.set_tab_title(2, tr(guide.name))
		var note = Bubble.new()
		note.name = "ReportGuide"
		guide.add_child(note)
		note.set_line(tr("阿禾 · 收摊手记"), guide_line, "waiter")

func _data_card(parent: Control) -> VBoxContainer:
	var card = Style.card()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", Style.inset(12,8))
	parent.add_child(card)
	var stack = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 7)
	card.add_child(stack)
	return stack

func _add_heading(parent: VBoxContainer, title: String, context := "") -> void:
	var row = HBoxContainer.new()
	parent.add_child(row)
	var heading = Style.text(title, 17)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(heading)
	if not context.is_empty():
		row.add_child(Style.text(context, 12, Style.MUTED))

func _add_focus(parent: VBoxContainer, report: Dictionary) -> void:
	var row = HBoxContainer.new()
	_data_card(parent).add_child(row)
	var focus = str(report.diagnosis.focus)
	var missing = int(report.get("refused_no_table", 0))
	row.add_child(Style.text(tr("主要瓶颈") if not focus.is_empty() or missing > 0 else tr("服务状态"), 15, Style.GOLD))
	var issue = tr("缺匹配餐桌 · %d 人") % missing if missing > 0 else tr("无明显瓶颈")
	if not focus.is_empty():
		var value = _diagnostic_value(report.diagnosis.stages[focus], focus)
		issue = tr(str(DIAGNOSTIC_TEXT[focus].label))
		if value != NO_SAMPLE:
			issue += " · " + value
	var headline = Style.text(issue, 15)
	headline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(headline)
	if not focus.is_empty():
		var locate = Style.button(tr("在餐厅定位"))
		locate.tooltip_text = DIAGNOSTIC_TEXT[focus].hint
		locate.custom_minimum_size.y = 30
		locate.pressed.connect(locate_requested.emit)
		row.add_child(locate)
		for state in ["normal", "hover", "pressed"]:
			var button_style = locate.get_theme_stylebox(state).duplicate()
			button_style.content_margin_top = 4
			button_style.content_margin_bottom = 4
			locate.add_theme_stylebox_override(state, button_style)

func _add_guest_outcomes(left: VBoxContainer, report: Dictionary) -> void:
	var summary = HBoxContainer.new()
	summary.add_theme_constant_override("separation", 8)
	left.add_child(summary)
	var ring = Charts.GuestRing.new()
	ring.name = "GuestOutcomes"
	ring.arrivals = int(report.arrived)
	summary.add_child(ring)
	var legend = VBoxContainer.new()
	legend.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	legend.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	legend.add_theme_constant_override("separation", 4)
	summary.add_child(legend)
	var missing = int(report.get("refused_no_table", 0))
	var outcomes = [
		[tr("完成用餐"), int(report.funnel.S), Style.GREEN],
		[tr("队满拒客"), int(report.funnel.R) - missing, Color("d9a562")],
		[tr("缺匹配餐桌"), missing, Color("cda4dc")],
		[tr("点单超时"), int(report.funnel.O), Color("d3c49d")],
		[tr("等餐超时"), int(report.funnel.F), Style.RED],
		[tr("清场未完餐"), int(report.funnel.C), Color("8aaad5")],
		[tr("其他离店"), int(report.funnel.get("Q", 0)), Style.MUTED],
	]
	for entry in outcomes:
		if entry[1] <= 0 and entry[0] != tr("完成用餐"): continue
		ring.segments.append({"count": entry[1], "tint": entry[2]})
		var item = HBoxContainer.new()
		legend.add_child(item)
		var marker = Panel.new()
		marker.custom_minimum_size = Vector2(9, 9)
		marker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		marker.add_theme_stylebox_override("panel", Style.box(entry[2], entry[2], 4, 0))
		item.add_child(marker)
		var name_label = Style.text(entry[0], 14, Style.MUTED)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item.add_child(name_label)
		item.add_child(Style.text(tr("%d 人") % entry[1], 14))
	ring.animate()

func _add_key_metrics(parent: VBoxContainer, report: Dictionary, previous: Dictionary) -> void:
	_add_heading(parent, tr("昨日对比") if not previous.is_empty() else tr("营业表现"), tr("│ 昨日") if not previous.is_empty() else "")
	var today_planned = int(report.planned)
	var prior_planned = int(previous.get("planned", 0))
	var today_complete = float(report.get("completed_before_midnight", report.completed)) * 100.0 / today_planned if today_planned > 0 else null
	var prior_complete = float(previous.get("completed_before_midnight", previous.get("completed", 0))) * 100.0 / prior_planned if prior_planned > 0 else null
	_comparison(parent, tr("午夜前完餐率"), today_complete, prior_complete, "%", 100, true)
	var today_refused = float(report.refused) * 100.0 / int(report.arrived) if int(report.arrived) > 0 else null
	var prior_refused = float(previous.get("refused", 0)) * 100.0 / int(previous.arrived) if int(previous.get("arrived", 0)) > 0 else null
	_comparison(parent, tr("拒客率"), today_refused, prior_refused, "%", 100, false)
	_comparison(parent, tr("平均排队"), _wait_average(report, "queue_wait_summary"), _wait_average(previous, "queue_wait_summary"), tr(" 秒"), 60, false)
	_comparison(parent, tr("平均等餐"), _wait_average(report, "food_wait_summary"), _wait_average(previous, "food_wait_summary"), tr(" 秒"), 60, false)

func _wait_average(report: Dictionary, key: String):
	var totals = report.get(key, {})
	return float(totals.average) if int(totals.get("count", 0)) > 0 else null

func _comparison(parent: VBoxContainer, caption: String, today, yesterday, unit: String, scale: float, higher_is_better: bool) -> void:
	var section = VBoxContainer.new()
	section.add_theme_constant_override("separation", 3)
	parent.add_child(section)
	var row = HBoxContainer.new()
	section.add_child(row)
	var title = Style.text(caption, 14, Style.MUTED)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	row.add_child(Style.text(tr("暂无记录") if today == null else "%.1f%s" % [today, unit], 14))
	var bar = Charts.ComparisonBar.new()
	bar.name = "ComparisonBar%d" % parent.get_child_count()
	var range_max = maxf(scale, maxf(float(today) if today != null else 0.0, float(yesterday) if yesterday != null else 0.0))
	bar.today = float(today) / range_max if today != null else 0.0
	bar.has_previous = yesterday != null
	bar.yesterday = float(yesterday) / range_max if bar.has_previous else 0.0
	if bar.has_previous:
		bar.tooltip_text = tr("昨日 %.1f%s") % [yesterday, unit]
		if today != null and absf(today - yesterday) >= .05:
			var better = (today > yesterday) == higher_is_better
			bar.change = Style.GREEN if better else Style.RED
			row.add_child(Style.text("%+.1f" % (today - yesterday), 13, bar.change))
	if not bar.tooltip_text.is_empty():
		section.tooltip_text = bar.tooltip_text
	bar.accessibility_name = caption + " " + row.get_child(1).text + " " + bar.tooltip_text
	section.add_child(bar)

func _add_details(details: VBoxContainer, report: Dictionary, previous: Dictionary, catalog: Dictionary) -> void:
	var columns = HBoxContainer.new()
	details.add_child(columns)
	var today_focus = str(report.diagnosis.focus)
	var previous_focus = str(previous.get("diagnosis", {}).get("focus", ""))
	var service = _data_card(columns)
	_add_heading(service, tr("服务明细"))
	var stages = GridContainer.new()
	stages.name = "ServiceBreakdown"
	stages.columns = 2 if previous.is_empty() else 3
	stages.add_theme_constant_override("h_separation", 16)
	stages.add_theme_constant_override("v_separation", 5)
	service.add_child(stages)
	_detail_cell(stages, tr("环节"), Style.MUTED, true)
	_detail_cell(stages, tr("今日"), Style.MUTED)
	if not previous.is_empty():
		_detail_cell(stages, tr("昨日"), Style.MUTED)
	for key in DIAGNOSTIC_TEXT:
		var stage = report.diagnosis.stages[key]
		var prior = previous.get("diagnosis", {}).get("stages", {}).get(key, {})
		var label = _detail_cell(stages, DIAGNOSTIC_TEXT[key].label, Style.GOLD if key == today_focus else Style.INK, true)
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		label.tooltip_text = DIAGNOSTIC_TEXT[key].hint
		if key == previous_focus:
			label.tooltip_text = tr("昨日重点\n") + label.tooltip_text
		var tint = Style.INK
		if int(stage.count) > 0 and int(prior.get("count", 0)) > 0 and absf(stage.average - prior.average) >= .05:
			tint = Style.GREEN if stage.average < prior.average else Style.RED
		var today = _detail_cell(stages, _diagnostic_value(stage, key), tint)
		today.name = key + "_today"
		if not previous.is_empty():
			var yesterday = _detail_cell(stages, _diagnostic_value(prior, key), Style.MUTED)
			yesterday.name = key + "_yesterday"
	service.add_child(HSeparator.new())
	_detail_pair(service, tr("座位占用率"), "%.0f%%" % (100.0 * report.seat_utilization))
	_detail_pair(service, tr("灶台使用率"), "%.0f%%" % (100.0 * report.stove_utilization))
	_detail_pair(service, tr("排队峰值"), tr("%d 人") % report.peak_queue)
	_detail_pair(service, tr("午夜后完餐"), tr("%d 人") % (int(report.completed) - int(report.get("completed_before_midnight", report.completed))))
	_detail_pair(service, tr("收尾用时"), tr("%.1f 秒") % (float(report.overtime_ticks) * int(catalog.chapter.simulation_tick_ms) / 1000.0))
	var kitchen = _data_card(columns)
	_add_heading(kitchen, tr("厨房与收入"))
	_detail_pair(kitchen, tr("制作"), tr("%d 份") % report.produced)
	_detail_pair(kitchen, tr("已食用"), tr("%d 份") % report.consumed)
	_detail_pair(kitchen, tr("损耗"), tr("%d 份") % report.discarded)
	_detail_pair(kitchen, tr("昨夜支出"), "%d$" % report.night_spend)
	if not report.income_recipes.is_empty():
		kitchen.add_child(HSeparator.new())
		_add_heading(kitchen, tr("菜品营收"))
		for id in report.income_recipes:
			_detail_pair(kitchen, catalog.recipes[id].name, "%d$" % report.income_recipes[id])
	kitchen.add_child(HSeparator.new())
	_add_heading(kitchen, tr("声望来源"))
	var earned = int(report.rep_base) + int(report.rep_buff)
	var wait_loss = int(report.wait_penalty_actual)
	var quality_loss = int(report.quality_penalty_actual)
	_detail_pair(kitchen, tr("完餐与增益"), "%+d" % earned)
	_detail_pair(kitchen, tr("等餐扣分"), str(-wait_loss))
	_detail_pair(kitchen, tr("品质扣分"), str(-quality_loss))
	var inspection = report.get("quality_inspection", {})
	var inspection_change = int(inspection.get("change", 0))
	if not inspection.is_empty():
		_detail_pair(kitchen, tr("食品安全检查"), "%+d" % inspection_change)
	var reward = int(report.reputation_change) - earned + wait_loss + quality_loss - inspection_change
	if reward != 0:
		_detail_pair(kitchen, tr("活动奖励"), "%+d" % reward)
	if not report.tips.is_empty():
		var tips = _data_card(details)
		_add_heading(tips, tr("调整建议"))
		for tip in report.tips:
			tips.add_child(Style.text(tip, 14, Style.MUTED, true))

func _detail_pair(parent: VBoxContainer, caption: String, value: String) -> void:
	var row = HBoxContainer.new()
	parent.add_child(row)
	_detail_cell(row, caption, Style.MUTED, true)
	_detail_cell(row, value, Style.INK)

func _detail_cell(parent: Container, value: String, tint: Color, expand := false) -> Label:
	var label = Style.text(value, 14, tint if value != NO_SAMPLE else Style.MUTED)
	if expand:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if value == NO_SAMPLE:
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		label.tooltip_text = tr("暂无样本")
	parent.add_child(label)
	return label

func _diagnostic_value(stage: Dictionary, key: String) -> String:
	if int(stage.get("count", 0)) == 0: return NO_SAMPLE
	return ("%.1f%%" if key == "queue" else tr("%.1f 秒")) % float(stage.average)
