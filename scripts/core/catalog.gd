extends RefCounted

const Grid = preload("res://scripts/core/layout.gd")
const Rules = preload("res://scripts/core/rules.gd")
const Decor = preload("res://scripts/core/decoration_effects.gd")

const DEFAULT_CHAPTER = "street_corner"

static func chapter_options() -> Array:
	var options = JSON.parse_string(FileAccess.get_file_as_string("res://data/chapters.json"))
	return options if options is Array else []

static func load_all(chapter_id: String = DEFAULT_CHAPTER) -> Dictionary:
	var result = {"chapter": {}, "recipes": {}, "buffs": {}, "guests": {}, "relics": {}, "decorations": {}, "errors": []}
	for file_name in ["chapter", "recipes", "buffs", "guests", "relics", "decorations"]:
		var path = "res://data/%s.json" % file_name
		var json = JSON.new()
		if not FileAccess.file_exists(path):
			result.errors.append(TranslationServer.translate("缺少配置：") + path)
			continue
		if json.parse(FileAccess.get_file_as_string(path)) != OK:
			result.errors.append(TranslationServer.translate("配置格式错误：") + path)
			continue
		if file_name == "chapter":
			if json.data is Dictionary: result.chapter = json.data
			else: result.errors.append(TranslationServer.translate("章节根节点必须是对象：") + path)
		else:
			if not json.data is Array:
				result.errors.append(TranslationServer.translate("配置列表必须是数组：") + path)
				continue
			for item in json.data:
				if not item is Dictionary or not item.has("id"):
					result.errors.append(TranslationServer.translate("配置条目缺少ID：") + path)
					continue
				if result[file_name].has(item.id):
					result.errors.append(TranslationServer.translate("重复 ID：") + str(item.id))
				result[file_name][item.id] = item
	if chapter_id != DEFAULT_CHAPTER:
		var config_path = ""
		for option in chapter_options():
			if str(option.id) == chapter_id:
				config_path = str(option.get("config", ""))
				break
		var overrides = JSON.parse_string(FileAccess.get_file_as_string(config_path)) if not config_path.is_empty() else null
		if not overrides is Dictionary:
			result.errors.append(TranslationServer.translate("无法加载章节：") + chapter_id)
		else:
			for key in overrides:
				if not result.chapter.has(key):
					result.errors.append(TranslationServer.translate("未知的章节配置项：") + str(key))
				elif overrides[key] is Dictionary and result.chapter[key] is Dictionary:
					result.chapter[key].merge(overrides[key], true)
				else:
					result.chapter[key] = overrides[key]
			result.chapter.id = chapter_id
	result.errors.append_array(validate(result))
	return result

static func validate(data: Dictionary) -> Array:
	var errors = []
	var c = data.chapter
	if c.is_empty():
		return [TranslationServer.translate("章节配置为空")]
	for key in ["id","config_version","save_version","chapter_days","day_duration_seconds","simulation_tick_ms","arrival_cutoff_ratio","fast_forward_multiplier","demand_curve","guaranteed_traffic_offer_days","initial_gold","initial_reputation","initial_attributes","attribute_caps","initial_menu","initial_layout","common_guest_template","base_customer_counts","rent_schedule","calendar","events","upgrade_rules","movement","quality_rules","upgrade_unlocks","trophy_zone","land_plots","completion_star_targets","weather"]:
		if not c.has(key): errors.append(TranslationServer.translate("章节缺少字段：") + key)
	for key in ["buff_shop_weights", "trophy_shop_weights", "guest_groups"]:
		if not c.has(key): errors.append(TranslationServer.translate("章节缺少字段：") + key)
	if not errors.is_empty(): return errors
	for field in ["initial_attributes","attribute_caps","upgrade_rules"]:
		if not c[field] is Dictionary: errors.append(TranslationServer.translate("章节属性格式错误：") + field)
	var quality_bonus = c.quality_rules.get("price_bonus_scale") if c.quality_rules is Dictionary else null
	if not _finite_number(quality_bonus) or quality_bonus < 0 or quality_bonus > 1:
		errors.append(TranslationServer.translate("品质溢价系数必须在 0 到 1 之间"))
	if not c.demand_curve is Array or c.demand_curve.is_empty(): errors.append(TranslationServer.translate("阶段客流配置不能为空"))
	if not errors.is_empty(): return errors
	for key in ["waiters","chefs","tables","menu_slots","queue_capacity","relic_slots"]:
		if not c.initial_attributes.has(key) or not c.attribute_caps.has(key) or not c.upgrade_rules.has(key):
			errors.append(TranslationServer.translate("缺少必要升级属性：") + key)
			continue
		var rule = c.upgrade_rules[key]
		if not rule is Dictionary or not rule.has_all(["base_count", "first_cost", "increment", "first_gold", "gold_increment"]):
			errors.append(TranslationServer.translate("升级价格字段缺失：") + key)
			continue
		if int(rule.get("step",1)) <= 0 or rule.first_cost < 0 or rule.increment < 0:
			errors.append(TranslationServer.translate("升级步长或声望成本无效：") + key)
		if not _whole_number(rule.first_gold) or int(rule.first_gold) <= 0 or not _whole_number(rule.gold_increment) or int(rule.gold_increment) < 0:
			errors.append(TranslationServer.translate("升级金币成本无效：") + key)
	if not errors.is_empty(): return errors
	for key in ["waiters","chefs","tables","menu_slots","queue_capacity","relic_slots"]:
		if not c.upgrade_unlocks.has(key):
			errors.append(TranslationServer.translate("升级缺少按天解锁配置：") + key)
			continue
		var gate = c.upgrade_unlocks[key]
		if not gate is Dictionary or not gate.has_all(["unlock_day","purchase_caps"]) or not gate.purchase_caps is Array:
			errors.append(TranslationServer.translate("升级解锁格式错误：") + key)
			continue
		if int(gate.unlock_day) < 0 or int(gate.unlock_day) > int(c.chapter_days): errors.append(TranslationServer.translate("升级解锁日期越界：") + key)
		var previous = 0
		for entry in gate.purchase_caps:
			if not entry is Dictionary or not entry.has_all(["day","max_purchases"]):
				errors.append(TranslationServer.translate("升级次数配置错误：") + key)
				continue
			if int(entry.day) <= previous or int(entry.day) > int(c.chapter_days) or int(entry.max_purchases) < 0:
				errors.append(TranslationServer.translate("升级次数日期或上限无效：") + key)
			previous = int(entry.day)
	var zone = c.trophy_zone
	if not zone is Dictionary or not zone.has_all(["left","top","right","bottom"]):
		errors.append(TranslationServer.translate("奖杯展示区配置缺失"))
	elif int(zone.left) < 1 or int(zone.top) < 1 or int(zone.right) >= int(c.initial_layout.width)-1 or int(zone.bottom) >= int(c.initial_layout.height)-1 or int(zone.left)>int(zone.right) or int(zone.top)>int(zone.bottom):
		errors.append(TranslationServer.translate("奖杯展示区越界"))
	for relic in data.relics.values():
		if not relic.has_all(["id","name","description","effect_type","effect_value","star_cost","color"]) or not _whole_number(relic.star_cost) or int(relic.star_cost) < 1:
			errors.append(TranslationServer.translate("奖杯配置字段或价格无效"))
		elif not Rules.BASE_MODIFIERS.has(relic.effect_type) or float(relic.effect_value) <= 0:
			errors.append(TranslationServer.translate("奖杯效果无效：") + str(relic.id))
	if data.relics.size() < 3: errors.append(TranslationServer.translate("奖杯候选不足三种"))
	if not c.land_plots is Array or c.land_plots.is_empty():
		errors.append(TranslationServer.translate("可解锁地块配置不能为空"))
	else:
		var claimed = {}
		var fixture_ids = {}
		var prior_day = 0
		for f in c.initial_layout.facilities:
			fixture_ids[str(f.id)] = true
		for plot in c.land_plots:
			if not plot is Dictionary or not plot.has_all(["id","name","kind","bounds","unlock_day","star_cost","fixtures","grant_chefs"]):
				errors.append(TranslationServer.translate("地块配置字段缺失"))
				continue
			if not plot.bounds is Dictionary or not plot.bounds.has_all(["left","top","right","bottom"]) or not plot.fixtures is Array:
				errors.append(TranslationServer.translate("地块边界或赠送家具格式无效"))
				continue
			var b = plot.bounds
			if int(plot.unlock_day) <= prior_day or int(plot.unlock_day) > int(c.chapter_days) or int(plot.star_cost) < 1 or int(plot.grant_chefs) < 0:
				errors.append(TranslationServer.translate("地块日期、价格或赠送厨师无效"))
			prior_day = int(plot.unlock_day)
			if int(b.left)<1 or int(b.top)<1 or int(b.right)>=int(c.initial_layout.width)-1 or int(b.bottom)>=int(c.initial_layout.height)-1 or int(b.left)>int(b.right) or int(b.top)>int(b.bottom):
				errors.append(TranslationServer.translate("地块范围越界"))
				continue
			for y in range(int(b.top),int(b.bottom)+1):
				for x in range(int(b.left),int(b.right)+1):
					var cell = Vector2i(x,y)
					if claimed.has(cell): errors.append(TranslationServer.translate("可解锁地块范围重叠"))
					claimed[cell] = true
			for f in plot.fixtures:
				if not f is Dictionary or not f.has_all(["id","name","type","pos"]):
					errors.append(TranslationServer.translate("地块赠送设施字段缺失"))
					continue
				var cell = Vector2i(Grid.vec(f.pos))
				if fixture_ids.has(str(f.id)) or cell.x<int(b.left) or cell.x>int(b.right) or cell.y<int(b.top) or cell.y>int(b.bottom): errors.append(TranslationServer.translate("地块赠送设施冲突或越界"))
				if f.type not in ["table","stove","trophy","slot","trophy_shop","decor_shop"]: errors.append(TranslationServer.translate("地块赠送设施类型无效"))
				if f.type=="trophy" and not data.relics.has(str(f.get("relic_id",""))): errors.append(TranslationServer.translate("地块赠送奖杯不存在"))
				fixture_ids[str(f.id)] = true
		for f in c.initial_layout.facilities:
			if claimed.has(Vector2i(Grid.vec(f.pos))): errors.append(TranslationServer.translate("初始家具占用锁定地块"))
		var base_layout = c.initial_layout.duplicate(true)
		base_layout.plots = c.land_plots.duplicate(true)
		base_layout.unlocked_plots = []
		errors.append_array(Grid.errors(base_layout))
		for plot in c.land_plots:
			base_layout.unlocked_plots.append(plot.id)
			base_layout.facilities.append_array(plot.fixtures)
			errors.append_array(Grid.errors(base_layout))
			var region = Grid.walkable_region(base_layout)
			var b = plot.bounds
			if not region.keys().any(func(cell): return cell.x >= int(b.left) and cell.x <= int(b.right) and cell.y >= int(b.top) and cell.y <= int(b.bottom)):
				errors.append(TranslationServer.translate("新地块与餐厅通路不连通：") + str(plot.id))
	if not errors.is_empty(): return errors
	if int(c.fast_forward_multiplier) <= 1: errors.append(TranslationServer.translate("快进倍率必须大于1"))
	var previous_day = 0
	for tier in c.demand_curve:
		if not tier is Dictionary or not tier.has_all(["from_day","normal","rare"]):
			errors.append(TranslationServer.translate("阶段客流缺少字段"))
			continue
		if int(tier.from_day) <= previous_day or int(tier.from_day) > int(c.chapter_days) or int(tier.normal) < 0 or int(tier.rare) < 0:
			errors.append(TranslationServer.translate("阶段客流日期或人数无效"))
		previous_day = int(tier.from_day)
	var first_day = int(c.demand_curve[0].get("from_day",0)) if c.demand_curve[0] is Dictionary else 0
	if previous_day == 0 or first_day != 1: errors.append(TranslationServer.translate("阶段客流必须从第1天开始"))
	if not c.guest_groups is Array:
		errors.append(TranslationServer.translate("客人组配置必须是列表"))
	else:
		var sizes = []
		var total_share = 0.0
		for group in c.guest_groups:
			if not group is Dictionary or not _whole_number(group.get("size")) or not _whole_number(group.get("from_day")) or not (group.get("share") is float or group.get("share") is int):
				errors.append(TranslationServer.translate("客人组缺少人数、开放日或客流占比"))
				continue
			var size = int(group.size)
			var share = float(group.share)
			if size not in [2, 4] or size in sizes or not is_finite(share) or share <= 0 or int(group.from_day) < 1 or int(group.from_day) > int(c.chapter_days):
				errors.append(TranslationServer.translate("客人组人数、开放日或客流占比无效"))
			sizes.append(size)
			total_share += share
		if total_share > 1.0: errors.append(TranslationServer.translate("客人组占比合计不可超过 100%"))
	if c.initial_gold<0 or c.initial_reputation<0:
		errors.append(TranslationServer.translate("初始资源不能为负"))
	if c.day_duration_seconds <= 0 or c.simulation_tick_ms <= 0:
		errors.append(TranslationServer.translate("模拟时长必须为正"))
	if c.arrival_cutoff_ratio <= 0 or c.arrival_cutoff_ratio > 1:
		errors.append(TranslationServer.translate("到店比例必须在 (0, 1] 内"))
	if not c.completion_star_targets is Array or c.completion_star_targets.is_empty():
		errors.append(TranslationServer.translate("完餐闪星必须配置阶段目标"))
	else:
		var target_day = 0
		for target in c.completion_star_targets:
			if not target is Dictionary or not target.has_all(["from_day", "percent"]):
				errors.append(TranslationServer.translate("完餐闪星缺少开放日或目标百分比"))
				continue
			var from_day = int(target.from_day)
			var percent = int(target.percent)
			if (target_day == 0 and from_day != 1) or from_day <= target_day or from_day > int(c.chapter_days) or percent < 1 or percent > 100 or percent != target.percent:
				errors.append(TranslationServer.translate("完餐闪星目标日期或百分比无效"))
			target_day = from_day
	var last_day = 0
	var last_amount = -1
	for rent in c.rent_schedule:
		if rent.day <= last_day or rent.amount <= last_amount or rent.day > c.chapter_days:
			errors.append(TranslationServer.translate("租金必须日期升序、金额递增且不越界"))
		last_day = int(rent.day)
		last_amount = int(rent.amount)
	if last_day != int(c.chapter_days):
		errors.append(TranslationServer.translate("最后营业日必须有房租"))
	for key in c.initial_attributes:
		if c.initial_attributes[key] <= 0 or c.initial_attributes[key] > c.attribute_caps[key]:
			errors.append(TranslationServer.translate("初始容量无效：") + key)
	for id in c.initial_menu:
		if not data.recipes.has(id):
			errors.append(TranslationServer.translate("初始菜单引用不存在：") + id)
	if c.initial_menu.is_empty():
		errors.append(TranslationServer.translate("初始菜单不能为空"))
	for recipe in data.recipes.values():
		if recipe.cook_seconds <= 0 or recipe.batch_yield < 1 or recipe.batch_yield > c.movement.chef_carry_capacity:
			errors.append(TranslationServer.translate("烹饪时长 / 产量无效：") + recipe.id)
		if recipe.base_value < 0 or recipe.base_value > 10000 or recipe.unlock_cost < 0:
			errors.append(TranslationServer.translate("菜品价格无效（首版基础价值支持0—10000）：") + recipe.id)
		var q = float(recipe.base_quality_multiplier)
		var qr = c.quality_rules
		if q < qr.minimum or q > qr.maximum or not is_equal_approx((q - qr.minimum) / qr.step, round((q - qr.minimum) / qr.step)):
			errors.append(TranslationServer.translate("品质档位无效：") + recipe.id)
	for buff in data.buffs.values():
		if not buff.has_all(["level", "duration_days", "max_stacks", "base_cost", "effect_type", "effect_per_stack"]) or not _whole_number(buff.level) or int(buff.level) < 1:
			errors.append(TranslationServer.translate("增益缺少有效的星级或效果字段：") + buff.id)
		elif buff.duration_days <= 0 or buff.max_stacks <= 0 or buff.base_cost < 0 or not Rules.BASE_MODIFIERS.has(buff.effect_type):
			errors.append(TranslationServer.translate("Buff 配置无效：") + buff.id)
	errors.append_array(_shop_weight_errors(c.buff_shop_weights, data.buffs, "level", int(c.chapter_days), TranslationServer.translate("增益")))
	errors.append_array(_shop_weight_errors(c.trophy_shop_weights, data.relics, "star_cost", int(c.chapter_days), TranslationServer.translate("奖杯")))
	for item in data.decorations.values():
		if not item.has_all(["name", "extent", "shape", "reach", "effect", "value", "price", "color"]) or not Decor.TARGETS.has(item.effect):
			errors.append(TranslationServer.translate("装饰缺少有效字段：") + item.id)
		elif not item.extent is Array or item.extent.size() != 2 or item.extent.any(func(n): return not _whole_number(n) or n < 1 or n > 3):
			errors.append(TranslationServer.translate("装饰占地无效：") + item.id)
		elif item.shape not in ["cross", "ring", "forward"] or not _whole_number(item.reach) or item.reach < 1 or not _whole_number(item.get("width", 1)) or item.get("width", 1) < 1 or not _finite_number(item.value) or item.value <= 0 or not _whole_number(item.price) or item.price < 1:
			errors.append(TranslationServer.translate("装饰范围或效果无效：") + item.id)
	errors.append_array(_weather_errors(c))
	errors.append_array(_calendar_errors(c, data.guests))
	var pool_weights = {"normal":0,"rare":0}
	if c.common_guest_template.payment_multiplier<=0 or c.common_guest_template.payment_multiplier>3:
		errors.append(TranslationServer.translate("首版章节消费倍率须在(0,3]，避免价格中间值溢出"))
	for guest in data.guests.values():
		if guest.rarity in pool_weights: pool_weights[guest.rarity]+=int(guest.pool_weight)
		if guest.type_payment_multiplier>6: errors.append(TranslationServer.translate("首版客人倍率不得超过6"))
		if not _whole_number(guest.get("food_penalty_per_cycle", 1)) or guest.get("food_penalty_per_cycle", 1) < 0 or not guest.get("unlimited_food_wait", false) is bool:
			errors.append(TranslationServer.translate("等餐规则无效：") + guest.id)
		if guest.base_reputation < 0 or guest.type_payment_multiplier < 0:
			errors.append(TranslationServer.translate("客人奖励不能为负"))
	if pool_weights.normal<=0 or pool_weights.rare<=0:
		errors.append(TranslationServer.translate("普通与稀有客人池必须有正权重"))
	return errors

static func _weather_errors(chapter: Dictionary) -> Array:
	var weather = chapter.weather
	if not weather is Dictionary or not weather.get("presets") is Dictionary or not weather.get("calendar") is Array:
		return [TranslationServer.translate("章节天气配置格式无效")]
	var errors = []
	var presets = weather.presets
	if not weather.get("default") is String or not presets.has(weather.default):
		errors.append(TranslationServer.translate("章节默认天气未定义"))
	for id in presets:
		var preset = presets[id]
		if not preset is Dictionary or not preset.get("name") is String or str(preset.name).is_empty() or not _finite_number(preset.get("rain")) or not _finite_number(preset.get("wind")) or not _finite_number(preset.get("cloud")):
			errors.append(TranslationServer.translate("天气预设缺少名称、雨量、风力或云量：") + str(id))
			continue
		if preset.rain < 0.0 or preset.rain > 1.0 or absf(preset.wind) > 1.0 or preset.cloud < 0.0 or preset.cloud > 1.0:
			errors.append(TranslationServer.translate("天气预设的雨量、风力或云量越界：") + str(id))
		if preset.has("thunder"):
			var thunder = preset.thunder
			if preset.rain <= 0.0 or not thunder is Dictionary or not _valid_weather_range(thunder.get("first_delay_seconds"), 1.0) or not _valid_weather_range(thunder.get("interval_seconds"), 4.0):
				errors.append(TranslationServer.translate("雷雨预设的打雷间隔无效：") + str(id))
	for entry in weather.calendar:
		if not entry is Dictionary or not _whole_number(entry.get("day")) or not _whole_number(entry.get("duration_days", 1)) or not entry.get("weather") is String or not presets.has(entry.weather):
			errors.append(TranslationServer.translate("天气日历引用无效"))
			continue
		var first = int(entry.day)
		var length = int(entry.get("duration_days", 1))
		if first < 1 or length < 1 or first + length - 1 > int(chapter.chapter_days):
			errors.append(TranslationServer.translate("天气日历日期越界：") + str(entry.weather))
	if chapter.events is Dictionary:
		for id in chapter.events:
			var event = chapter.events[id]
			if event is Dictionary and event.has("weather") and (not event.weather is String or not presets.has(event.weather)):
				errors.append(TranslationServer.translate("事件引用了未知天气：") + str(id))
	return errors

static func _valid_weather_range(value: Variant, minimum: float) -> bool:
	return value is Array and value.size() == 2 and _finite_number(value[0]) and _finite_number(value[1]) and float(value[0]) >= minimum and float(value[1]) >= float(value[0])

static func _calendar_errors(chapter: Dictionary, guests: Dictionary) -> Array:
	if not chapter.calendar is Array or not chapter.events is Dictionary: return [TranslationServer.translate("事件日历格式无效")]
	var errors = []
	var peak_days = {}
	var major_ids = {}
	for entry in chapter.calendar:
		if not entry is Dictionary or not _whole_number(entry.get("day")) or not _whole_number(entry.get("duration_days", 1)) or not chapter.events.get(entry.get("event")) is Dictionary:
			errors.append(TranslationServer.translate("事件日历引用无效"))
			continue
		var first = int(entry.day)
		var length = int(entry.get("duration_days", 1))
		if first < 1 or length < 1 or first + length - 1 > int(chapter.chapter_days):
			errors.append(TranslationServer.translate("事件日历日期越界：") + str(entry.event))
			continue
		var event = chapter.events[entry.event]
		if event.has("notice"):
			if major_ids.has(entry.event): errors.append(TranslationServer.translate("重大事件只能安排一次：") + str(entry.event))
			major_ids[entry.event] = true
			errors.append_array(_notice_errors(event, str(entry.event)))
		if event.has("arrival_peak"):
			var peak = event.arrival_peak
			if not peak is Dictionary or not peak.has_all(["start_minute", "end_minute", "share"]):
				errors.append(TranslationServer.translate("到店高峰缺少时段或比例：") + str(entry.event))
			else:
				var cutoff_minute = 540 + 720 * float(chapter.arrival_cutoff_ratio)
				if float(peak.start_minute) <= 540 or float(peak.end_minute) >= cutoff_minute or float(peak.start_minute) >= float(peak.end_minute) or float(peak.share) <= 0 or float(peak.share) >= 1:
					errors.append(TranslationServer.translate("到店高峰时段或比例无效：") + str(entry.event))
			for date in range(first, first + length):
				if peak_days.has(date): errors.append(TranslationServer.translate("同一营业日只能配置一个到店高峰"))
				peak_days[date] = true
		var traffic_multiplier = event.get("regular_traffic_multiplier", 1.0)
		if not _finite_number(traffic_multiplier) or traffic_multiplier < 0.0 or traffic_multiplier > 1.0:
			errors.append(TranslationServer.translate("常规客流倍率无效：") + str(entry.event))
		var has_guest = event.has("special_guest")
		var visits = event.get("special_visits", [])
		var visits_valid = visits is Array and (not visits.is_empty() if has_guest else visits.is_empty())
		if not visits_valid:
			errors.append(TranslationServer.translate("特殊客人来访配置无效：") + str(entry.event))
		else:
			var cutoff = float(chapter.day_duration_seconds) * float(chapter.arrival_cutoff_ratio)
			for visit in visits:
				if not visit is Dictionary or not _whole_number(visit.get("day_offset")) or int(visit.day_offset) < 0 or int(visit.day_offset) >= length or not _whole_number(visit.get("size")) or int(visit.size) not in [1, 2, 4] or not _finite_number(visit.get("spawn_seconds")) or float(visit.spawn_seconds) < 0.0 or float(visit.spawn_seconds) >= cutoff:
					errors.append(TranslationServer.translate("特殊客人的日期、人数或到店时间无效：") + str(entry.event))
					visits_valid = false
					break
		if has_guest and (not guests.has(event.special_guest) or guests[event.special_guest].rarity != "special"):
			errors.append(TranslationServer.translate("特殊客人引用无效：") + str(entry.event))
		if event.has("quality_inspection"):
			var inspection = event.quality_inspection
			if not inspection is Dictionary or not inspection.has_all(["neutral_quality", "reputation_per_percentage_point", "limit"]) or not has_guest or not visits_valid or visits.size() != 1 or not _finite_number(inspection.neutral_quality) or inspection.neutral_quality <= 0.0 or not _whole_number(inspection.reputation_per_percentage_point) or inspection.reputation_per_percentage_point < 1 or not _whole_number(inspection.limit) or inspection.limit < 50:
				errors.append(TranslationServer.translate("食品安全检查规则无效：") + str(entry.event))
	return errors

static func _notice_errors(event: Dictionary, id: String) -> Array:
	if not event.notice is Dictionary: return [TranslationServer.translate("重大事件公告格式无效：") + id]
	var errors = []
	var art = str(event.notice.get("art", ""))
	if (art.is_empty() and not event.has("quality_inspection")) or (not art.is_empty() and not ResourceLoader.exists(art) and not FileAccess.file_exists(art)):
		errors.append(TranslationServer.translate("重大事件海报缺失：") + id)
	var traffic = event.get("traffic", {})
	if not traffic is Dictionary:
		errors.append(TranslationServer.translate("事件客流倍率格式无效：") + id)
	else:
		for category in traffic:
			var amount = traffic[category]
			if category not in ["normal", "rare", "2", "4"] or not _finite_number(amount) or float(amount) < -1:
				errors.append(TranslationServer.translate("事件客流倍率无效：") + id)
	for field in ["payment_pct", "quality_expectation_add"]:
		if not _finite_number(event.get(field, 0)): errors.append(TranslationServer.translate("事件品质或收入倍率无效：") + id)
	if not _valid_event_reward(event.notice.get("grant", {})): errors.append(TranslationServer.translate("重大事件确认奖励无效：") + id)
	if event.notice.has("goal"):
		var goal = event.notice.goal
		if not goal is Dictionary or not _whole_number(goal.get("daily_stars")) or int(goal.daily_stars) not in [1, 2, 3] or not _valid_event_reward(goal.get("reward")) or goal.reward.is_empty():
			errors.append(TranslationServer.translate("重大事件目标无效：") + id)
	return errors

static func _finite_number(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value))

static func _valid_event_reward(reward: Variant) -> bool:
	if not reward is Dictionary: return false
	for resource in reward:
		if resource not in ["gold", "reputation"] or not _whole_number(reward[resource]) or int(reward[resource]) <= 0: return false
	return true

static func _whole_number(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value) and float(value) == floorf(value))

static func _shop_weight_errors(stages: Variant, items: Dictionary, level_field: String, chapter_days: int, title: String) -> Array:
	if not stages is Array or stages.is_empty():
		return [title + TranslationServer.translate("等级权重表不能为空")]
	var levels = {}
	for item in items.values():
		if _whole_number(item.get(level_field)):
			levels[str(int(item[level_field]))] = true
	var errors = []
	var previous = 0
	for stage in stages:
		if not stage is Dictionary or not _whole_number(stage.get("from_day")) or not stage.get("weights") is Dictionary:
			errors.append(title + TranslationServer.translate("等级权重缺少日期或权重"))
			continue
		var start = int(stage.from_day)
		if (previous == 0 and start != 1) or start <= previous or start > chapter_days:
			errors.append(title + TranslationServer.translate("等级权重须从第 1 天开始并按日期递增"))
		previous = start
		var total = 0
		for level in stage.weights:
			var weight = stage.weights[level]
			if not levels.has(str(level)) or not _whole_number(weight) or int(weight) < 0:
				errors.append(title + TranslationServer.translate("等级权重包含无效星级或权重"))
			else:
				total += int(weight)
		if total <= 0: errors.append(title + TranslationServer.translate("每个阶段至少需要一个正权重"))
	return errors
