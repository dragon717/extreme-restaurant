extends Node

const Grid = preload("res://scripts/core/layout.gd")
const Store = preload("res://scripts/core/save_store.gd")
const Bubble = preload("res://scripts/ui/speech_bubble.gd")
const Style = preload("res://scripts/ui/style.gd")
const NAME = "阿禾 · 前厅"
const MERGE = "夜晚用左键按住一张餐桌，等它抬起后拖到同规格的桌上，再松手。两张单人桌合成双人桌，两张双人桌合成四人桌。"
const EVENT_ENTRY = "重大事件预告会出现在前一份日报的「明日预告」。公告按钮会在事件生效期间的夜晚出现。点右上角红色的「重大事件」，查看生效日期、客流变化和限时任务。带奖励的公告会显示「确定并领取」。"
const HOURS = "21:00 停止接待新客，00:00 解散店外队伍。店内客人会继续点餐、用餐和结账。最后一位客人离开后才出日报。"
const REPORT_LINES = {
	"ordering": "客人选好菜后还在等点单。点「在餐厅定位」，看看等得最久的桌离服务员有多远。",
	"kitchen": "等餐主要卡在出餐口之前。点「在餐厅定位」，检查交单、灶台和厨师搬餐的路线。",
	"delivery": "餐已经到了出餐口，客人还在等。点「在餐厅定位」，检查服务员取餐到客桌的路。",
	"queue": "有人因为队伍满员或等到午夜而没能入座。点「在餐厅定位」看入口，左栏还会单独统计缺匹配餐桌的客人。",
	"": "左边看客人的去向，右边找经营卡在哪一步。调整布局后，可以对照下一份日报。",
}

var app
var profile_path: String
var mode := "ask"
var seen: Dictionary = {}
var stage := ""
var blocks_clock := false
var bubble
var order_id := 0
var guest_id := 0
var highlighted: Control
var original_tint := Color.WHITE
var last_night := -1
var opens_after_tables := false
var report_day := -1
var report_lines: Array[String] = []

func setup(game, path: String) -> void:
	app = game
	profile_path = path
	var saved = Store.read_checkpoint(path)
	mode = str(saved.get("mode", "ask"))
	if saved.get("seen") is Dictionary: seen = saved.seen

func _persist() -> void:
	var error = Store.write_checkpoint({"mode": mode, "seen": seen}, profile_path)
	if not error.is_empty(): app._notice(error, true)

func _mark(key: String) -> void:
	if not seen.has(key):
		seen[key] = true
		_persist()

func start_visit() -> void:
	clear_line()
	last_night = -1
	order_id = 0
	guest_id = 0
	report_day = -1
	report_lines.clear()
	app.world.guide_camera_manual = false
	if app.sim.phase == "NIGHT":
		if not seen.has("tour") and (mode == "on" or (mode == "ask" and app.sim.day == 1)):
			_intro()
		else:
			night()

func skip() -> void:
	clear_line()
	mode = "off"
	_persist()

func replay() -> void:
	clear_line()
	mode = "on"
	seen = {}
	last_night = -1
	order_id = 0
	guest_id = 0
	report_day = -1
	report_lines.clear()
	app.world.guide_camera_manual = false
	_persist()
	if app.sim.phase == "REPORT": app._show_report()
	else: _intro(true)

func _speaker() -> String:
	if app.sim.phase == "NIGHT": return "preview_waiter_0"
	for worker in app.sim.staff:
		if worker.role == "waiter": return "s_%d" % worker.id
	return ""

func _speaker_cell() -> Vector2:
	if app.sim.phase == "NIGHT":
		var starts = app.sim.layout.get("waiter_starts", [])
		return Grid.vec(starts[0] if not starts.is_empty() else app.sim.layout.waiter_spawn)
	for worker in app.sim.staff:
		if worker.role == "waiter": return worker.pos
	return Grid.vec(app.sim.layout.entrance)

func _fixture(id: String) -> Vector2:
	return Grid.vec(Grid.find(app.sim.layout, id).pos)

func _line(key: String, message: String, seconds := -1.0) -> void:
	if is_instance_valid(bubble): bubble.dismiss()
	stage = key
	bubble = app.world.say(_speaker(), tr(NAME), message, seconds, true)

func clear_line() -> void:
	if is_instance_valid(bubble): bubble.dismiss()
	bubble = null
	stage = ""
	opens_after_tables = false
	blocks_clock = false
	if is_instance_valid(highlighted):
		highlighted.self_modulate = original_tint
	highlighted = null
	app.world.greeting_actor = ""
	app.world.end_guide_shot()

func _highlight(control: Control) -> void:
	highlighted = control
	original_tint = control.self_modulate
	control.self_modulate = Color("ffe19a")

func _process(_delta: float) -> void:
	if not stage.is_empty() and not is_instance_valid(bubble):
		clear_line()

func _intro(from_beginning := false) -> void:
	app.world.greeting_actor = _speaker()
	app.world.guide_shot(_speaker_cell(), 1.55)
	blocks_clock = true
	if mode == "ask" or from_beginning:
		_line("welcome", tr("老板，我是跑堂的阿禾。开店后，厨师和服务员会自己接单上菜。我先带你认两个柜台，再看看怎么合桌。"))
		bubble.add_choice(tr("跟你看看"), _accept, true)
		bubble.add_choice(tr("我自己逛"), skip)
	else:
		_counter(seen.has("order_counter"))

func _accept() -> void:
	mode = "on"
	_persist()
	_counter(false)

func _counter(at_pass: bool) -> void:
	app.world.greeting_actor = ""
	var order = _fixture("order")
	var counter = _fixture("pass")
	var target = counter if at_pass else order
	app.world.guide_shot((order + counter) * 0.5, 1.4, [target])
	if at_pass:
		_line("pass_counter", tr("这是出餐口。厨师把做好的菜放在这里，服务员再取餐送到客桌。"))
		bubble.add_choice(tr("记住了"), _finish_tour, true)
	else:
		_line("order_counter", tr("这是订单口。服务员给客人点单后，会把订单送到这里，厨师从这里接单。"))
		bubble.add_choice(tr("再看出餐口"), _next_counter, true)
	bubble.add_choice(tr("跳过引导"), skip)

func _next_counter() -> void:
	_mark("order_counter")
	_counter(true)

func _finish_tour() -> void:
	clear_line()
	_mark("tour")
	if app.sim.phase != "NIGHT": return
	if not seen.has("tables"):
		teach_tables(true)
	else:
		_show_open_prompt()

func _show_open_prompt() -> void:
	var dish = app.sim.recipes[app.sim.menu[0]]
	_line("open", tr("今天的菜单上有%s，一锅出%d份。准备好了就点下方「开店」，我会带你看第一桌怎么点餐。") % [tr(str(dish.name)), dish.batch_yield], 12)
	_highlight(app.ui.open)

func _practice_pair() -> Array:
	var tables = Grid.facilities(app.sim.layout, "table")
	for seats in [1, 2]:
		for target in tables:
			if Grid.table_size(target) != seats: continue
			for source in tables:
				if source.id == target.id or Grid.table_size(source) != seats: continue
				if app.sim.preview_table_merge(source, target).ok: return [source, target]
	return []

func teach_tables(before_open := false) -> void:
	if app.sim.phase != "NIGHT": return
	clear_line()
	app.world.guide_camera_manual = false
	app.world.cancel_placement()
	app._clear_inspector()
	app.ui.slot_panel.hide()
	opens_after_tables = before_open
	var pair = _practice_pair()
	if pair.is_empty():
		_line("tables", tr(MERGE) + tr("\n合成需要留出桌面和走道。"))
	else:
		var start = Grid.vec(pair[0].pos)
		var target = Grid.vec(pair[1].pos)
		app.world.guide_shot((start + target) * .5, 1.18, [start, target])
		var delta = start - target
		var side = tr("右边") if delta.x > 0 else tr("左边")
		if absf(delta.y) > absf(delta.x): side = tr("下方") if delta.y > 0 else tr("上方")
		_line("tables", tr("同一组客人只坐人数相同的桌。用左键按住%s高亮的%s，等它抬起后拖到另一张高亮桌上，再松手。") % [side, tr(Grid.table_label(Grid.table_size(pair[0])))])
	bubble.add_choice(tr("稍后再试"), _finish_tables)

func table_merged(seats: int) -> void:
	if stage != "tables": return
	_mark("tables")
	app.world.end_guide_shot()
	var next = tr("两张双人桌还能合成 2×2 的四人桌。") if seats == 2 else tr("四人桌只接待四人组，记得保留单人桌和双人桌。")
	_line("tables_done", tr("合成成功。%s\n%s。选中多人桌后可用右下角的拆分图标或按 %s。") % [next, _group_dates(), app.keys.text("split")])
	bubble.add_choice(tr("继续"), _finish_tables, true)

func _finish_tables() -> void:
	var before_open = opens_after_tables
	_mark("tables")
	clear_line()
	if before_open: _show_open_prompt()

func opened() -> void:
	if mode == "ask" and stage == "welcome":
		skip()
	else:
		clear_line()
		if mode == "on": _mark("tour")
	order_id = 0

func after_step() -> void:
	if mode != "on" or blocks_clock or app.modal_layer != null or seen.has("payment") or app.sim.phase != "DAY": return
	var sim = app.sim
	if not seen.has("guest"):
		for guest in sim.active_customers.values():
			if guest.state in ["READY", "TAKING"]:
				guest_id = guest.id
				app.world.guide_shot(guest.pos, 1.38, [_fixture(guest.seat)])
				_line("guest", tr("高亮这桌已经选好菜，正等服务员过去点单。点「查看客人」能看他选了什么，我先把营业计时停住。"))
				blocks_clock = true
				bubble.add_choice(tr("查看客人"), _inspect_guest, true)
				bubble.add_choice(tr("继续营业"), finish_guest)
				return
	elif not seen.has("delivery"):
		if order_id == 0:
			for order in sim.orders.values():
				if order.supply == "WITH_WAITER" and order.status == "ACTIVE":
					order_id = order.id
					var worker = sim.staff[int(order.delivery_owner) - 1]
					app.world.guide_shot(worker.pos, 1.36, [_fixture(order.seat)])
					_line("delivery", tr("看正在端盘的服务员。他刚从出餐口取到菜，接下来会送到点这道菜的客桌。"))
					break
		else:
			var order = sim.orders[order_id]
			if int(order.get("served_tick", -1)) >= 0:
				_mark("delivery")
				clear_line()
			elif order.status != "ACTIVE" or order.supply != "WITH_WAITER":
				order_id = 0
				clear_line()
			elif int(order.delivery_owner) > 0 and app.world.guide_camera_active:
				app.world.guide_target = sim.staff[int(order.delivery_owner) - 1].pos
	if sim.stats.payer_count > 0:
		clear_line()
		_mark("delivery")
		_mark("payment")
		_line("payment", tr("第一笔饭钱到账了。顶栏的「今日营收」记录今天赚了多少，金币是现在能花的余额。想暂停观察，可以按 %s。") % app.keys.text("pause"), 10)
		_highlight(app.ui.income_label)

func _inspect_guest() -> void:
	app._inspect("customer", str(guest_id))
	_line("guest", tr("右侧信息框显示客人的状态和菜名。等餐时，这里还会显示剩余耐心。看完再继续营业。"))
	bubble.add_choice(tr("继续营业"), finish_guest, true)

func finish_guest() -> void:
	if stage == "guest":
		_mark("guest")
		clear_line()

func night() -> void:
	if mode != "on" or app.sim.phase != "NIGHT" or last_night == app.sim.day: return
	last_night = app.sim.day
	clear_line()
	var sim = app.sim
	if not seen.has("tour"):
		_intro()
		return
	var rent = sim.next_rent()
	var plot = sim.next_land_plot()
	if not seen.has("rent") and int(rent.get("day", -1)) == sim.day:
		_mark("rent")
		_line("rent", tr("顶栏左边是下次房租。今天营业结束会扣 %d 金币，采购前记得留足。") % int(rent.amount), 9)
		_highlight(app.ui.rent_card)
	elif not seen.has("major_event") and not app.major_notice.is_empty():
		_line("major_event", tr("右上角红色的「重大事件」亮了。开店前点开「%s」，看看哪几天生效、客流怎么变。有奖励时，记得点公告底部领取。") % tr(str(app.major_notice.name)))
		_highlight(app.ui.major_event)
		bubble.add_choice(tr("查看公告"), app._show_major_event, true)
		bubble.add_choice(tr("稍后查看"), clear_line)
	elif not seen.has("tables"):
		teach_tables()
	elif sim.decoration_shop_unlocked() and not seen.has("decor_shop"):
		show_new_shop("decor_shop")
	elif sim.trophy_shop_unlocked() and not seen.has("gallery_shop"):
		show_gallery()
	elif sim.purchase_unlocked() and not seen.has("shop_slot"):
		show_new_shop("slot")
	elif plot.get("id") == "kitchen_extension" and sim.day >= int(plot.unlock_day) and not seen.has("plot_kitchen_extension"):
		_mark("plot_kitchen_extension")
		var bounds = plot.bounds
		var cell = Vector2((bounds.left + bounds.right) * 0.5, (bounds.top + bounds.bottom) * 0.5)
		app.world.guide_shot(cell, 1.25, [cell])
		_line("kitchen", _plot_text(plot), 10)
	elif sim.day == 1 and sim.chapter.id == "market_lane" and not seen.has("market_lane"):
		_mark("market_lane")
		_line("market_lane", tr("这回咱们赶集。拼盘小食一锅四份，桌子翻得也快。开门时一起看看第一波客人。"), 8)
	elif not seen.has("reputation"):
		for key in sim.chapter.upgrade_rules:
			if sim.upgrade_status(key).ok:
				_mark("reputation")
				var cell = _fixture("cashier")
				app.world.guide_shot(cell, 1.25, [cell])
				_line("reputation", tr("点收银台，再选「招聘与改造」。桌位和员工都要花声望与金币。招聘与改造页会列出两种价格和下次房租，手头的钱也得留一份给房东。"), 9)
				break

func _plot_text(plot: Dictionary) -> String:
	var price = int(plot.star_cost)
	var missing = price - int(app.sim.stars)
	var message: String
	match str(plot.id):
		"purchase_annex": message = tr("花 %d 颗闪星打开采购小厅。采购处每晚到货菜谱和增益。") % price
		"decor_studio": message = tr("花 %d 颗闪星开放装饰商店。装饰放下后，会为范围内的餐桌、员工或灶台提供效果。") % price
		"kitchen_extension": message = tr("花 %d 颗闪星扩开厨房，就多一口灶，也多一位厨师。") % price
		"trophy_gallery": message = tr("花 %d 颗闪星可开放奖杯展廊和旁边的奖杯商店，还会送一座铜摆钟。") % price
		"east_dining": message = tr("东边一开就多四张桌，花 %d 颗闪星。门口没坐上的客人，这回有地方请了。") % price
		"south_dining": message = tr("南边还能添三张桌，花 %d 颗闪星。这回你来掌眼，端到最远那桌得走多远？") % price
		_: message = tr("%s需要 %d 颗闪星。") % [tr(str(plot.name)), price]
	if missing > 0: message += tr(" 还差 %d 颗，攒够了再来。") % missing
	return message

func plot_note(parent: Control, selected: String) -> void:
	var plot = app.sim.next_land_plot()
	if app.sim.phase != "NIGHT" or plot.is_empty() or app.sim.day < int(plot.unlock_day): return
	if not selected.is_empty() and selected != str(plot.id): return
	inline_note(parent, "plot_" + str(plot.id), _plot_text(plot))

func show_gallery() -> void:
	if mode != "on" or seen.has("gallery_shop") or not app.sim.trophy_shop_unlocked(): return
	clear_line()
	app.world.guide_camera_manual = false
	var shop = Vector2(app.sim.trophy_shop_cell())
	app.world.guide_shot(shop, 1.25, [shop])
	_line("gallery_gift", tr("奖杯商店开门了，就在展廊里。用闪星买奖杯，点右下角的背包图标取出。放到展廊里亮起的格子后，奖杯就会生效。"))
	bubble.add_choice(tr("查看奖杯商店"), app._show_trophy_shop, true)
	bubble.add_choice(tr("稍后再看"), clear_line)

func trophy_shop_opened() -> void:
	if stage == "gallery_gift": clear_line()
	if mode == "on": _mark("gallery_shop")

func show_new_shop(id: String) -> void:
	var flag = "shop_slot" if id == "slot" else "decor_shop"
	if mode != "on" or seen.has(flag): return
	clear_line()
	var cell = _fixture(id)
	app.world.guide_shot(cell, 1.25, [cell])
	var message = tr("采购小厅开门了。今晚可以用金币买新菜谱和营业增益。") if id == "slot" else tr("装饰商店开门了。买到的装饰在建造背包里，摆放时会亮出效果范围。")
	_line(flag, message)
	if id == "slot":
		bubble.add_choice(tr("查看采购处"), func(): app._show_purchase_page(), true)
	else:
		bubble.add_choice(tr("查看装饰商店"), app._show_decoration_shop, true)
	bubble.add_choice(tr("稍后再看"), clear_line)

func shop_opened(id: String) -> void:
	var flag = "shop_slot" if id == "slot" else "decor_shop"
	if stage == flag: clear_line()
	if mode == "on": _mark(flag)

func purchase() -> void:
	if mode != "on" or blocks_clock or app.sim.phase != "NIGHT" or seen.has("purchase"): return
	clear_line()
	_mark("purchase")
	_line("purchase", tr("点右侧「进入采购」。买到的菜谱会永久进收藏，增益只在标明的营业日内生效。"), 10)
	_highlight(app.ui.enter_shop)

func placement() -> void:
	if mode != "on" or seen.has("placement"): return
	_mark("placement")
	clear_line()
	_line("placement", tr("点击餐厅里的空格放置新设施，给座位和柜台留出通路。暂时不用的设施，可以在右下角「建造」背包里找回。"), 8)

func event_opened() -> void:
	if stage == "major_event": clear_line()
	if mode == "on": _mark("major_event")

func build_opened() -> void:
	if mode != "on" or seen.has("build_catalog"): return
	_mark("build_catalog")
	if stage.is_empty():
		_line("build", tr("在下方选物件，再到地图上放置。选中场景里的设施时，可以用右下角的图标移动、旋转或收起。"), 9)

func _build_text() -> String:
	return tr("夜晚点右下角的锤子，或按 %s 打开底部建造目录。按类别找物件，选中后点地图放置。隔墙可以拖成一排。按 Esc 取消当前操作，再按 Esc 关闭目录。") % app.keys.text("build")

func _group_dates() -> String:
	var dates: Array[String] = []
	for group in app.sim.chapter.guest_groups:
		dates.append(tr("%d 人组从第 %d 天来店") % [int(group.size), int(group.from_day)])
	return "，".join(dates)

func populate_handbook(parent: VBoxContainer) -> void:
	var sections = [
		[tr("合桌与客人组"), tr(MERGE) + "\n" + _group_dates() + tr("。客人组只坐人数相同的桌，店里没有对应的桌就会离开。\n选中多人桌后，点右下角的拆分图标或按 %s，可以逐级拆回。") % app.keys.text("split")],
		[tr("重大事件"), tr(EVENT_ENTRY)],
		[tr("奖杯商店"), tr("解锁右上角的奖杯展廊后，点外墙上的奖杯商店。用闪星购买，摆进展廊后生效。")],
		[tr("建造和布置"), _build_text() + tr("\n选中设施后，右下角会显示可用工具。把鼠标停在图标上可查看名称。也可以按 %s 旋转。") % app.keys.text("rotate")],
		[tr("营业与复盘"), tr("服务员点单后送到订单口，厨师做好后放到出餐口，服务员再取餐上桌。\n") + tr(HOURS) + tr("\n日报的「在餐厅定位」会标出瓶颈。缺匹配餐桌时，先按客组人数调整桌型。")],
	]
	for section in sections:
		var heading = Style.text(section[0], 18, Style.GOLD)
		parent.add_child(heading)
		parent.add_child(Style.text(section[1], 15, Style.INK, true))

func inline_note(parent: Control, key: String, message: String) -> void:
	if mode != "on" or seen.has(key): return
	_mark(key)
	var note = Bubble.new()
	parent.add_child(note)
	note.set_line(NAME, message, "waiter")

func report_text(report: Dictionary, forecast: String) -> String:
	clear_line()
	if mode != "on": return ""
	if report_day != int(report.day):
		report_day = int(report.day)
		report_lines.clear()
	var focus = str(report.diagnosis.focus)
	if not seen.has("report") or (not focus.is_empty() and not seen.has("report_focus")):
		report_lines.append(tr(REPORT_LINES.get(focus, REPORT_LINES[""])))
		if not focus.is_empty(): _mark("report_focus")
	if not seen.has("report"):
		report_lines.append(tr("零拒客、等餐无扣分也无超时、午夜前完餐人数比例达标。三个目标各值一颗闪星。"))
		_mark("report")
	if not forecast.is_empty() and not seen.has("rush"):
		report_lines.append(tr("看「明日预告」里的客流高峰，确认哪段时间会集中来客。开店前，左上角也会显示时段。"))
		_mark("rush")
	return "\n".join(report_lines)
