extends VBoxContainer

const Style = preload("res://scripts/ui/style.gd")
const Trophies = preload("res://scripts/core/trophies.gd")
const TrophyArt = preload("res://scripts/visuals/trophy_art.gd")
const Grid = preload("res://scripts/core/layout.gd")

signal draw_requested
signal bag_requested
signal place_requested(facility_id: String)

var sim
var opening := false
var reel := Reel.new()
var buy: Button
var skip: Button
var bag: Button
var place: Button
var balance: Label
var ledger: Label
var effect: Label
var prize: Label
var odds_labels: Array[Label] = []

func _ready() -> void:
	name = "TrophyBoxContents"
	add_theme_constant_override("separation", 11)
	var header := HBoxContainer.new()
	add_child(header)
	ledger = Style.text("", 14, Style.MUTED)
	ledger.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(ledger)
	balance = Style.readout(header, "coins", "", "当前金币余额", Style.GOLD)
	reel.custom_minimum_size.y = 248
	reel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reel.clip_contents = true
	add_child(reel)
	reel.opened.connect(_finish_opening)
	var probabilities := HBoxContainer.new()
	probabilities.add_theme_constant_override("separation", 6)
	add_child(probabilities)
	for grade in range(1, 6):
		var tint = Trophies.grade_color(grade)
		var label = Style.text("", 14, tint)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.tooltip_text = tr("营业日越晚、累计开箱越多，高品质越常见。")
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		probabilities.add_child(label)
		odds_labels.append(label)
	var hint := VBoxContainer.new()
	hint.add_theme_constant_override("separation", 3)
	add_child(hint)
	prize = Style.text("", 18, Style.INK)
	hint.add_child(prize)
	effect = Style.text("", 14, Style.MUTED, true)
	hint.add_child(effect)
	var actions := HBoxContainer.new()
	add_child(actions)
	buy = Style.button("", true)
	buy.name = "OpenTrophyBox"
	buy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buy.pressed.connect(draw_requested.emit)
	actions.add_child(buy)
	skip = Style.button("跳过动效")
	skip.name = "SkipTrophyOpening"
	skip.pressed.connect(reel.finish)
	actions.add_child(skip)
	place = Style.button("摆放奖杯")
	place.name = "PlaceDrawnTrophy"
	place.pressed.connect(_place)
	actions.add_child(place)
	bag = Style.button("奖杯背包")
	bag.name = "OpenDrawTrophyBag"
	bag.pressed.connect(bag_requested.emit)
	actions.add_child(bag)

func configure(simulation) -> void:
	sim = simulation
	if not sim.last_trophy_id.is_empty(): reel.show_reward(sim.relic_defs[sim.last_trophy_id])
	refresh()

func refresh(offer: Dictionary = {}) -> void:
	var quote = sim.trophy_box_offer() if offer.is_empty() else offer
	balance.text = tr("%d 金币") % sim.gold
	ledger.text = tr("今晚第 %d 箱 · 累计 %d 箱") % [sim.trophy_draws_today + (0 if opening else 1), sim.trophy_draws_total]
	ledger.tooltip_text = tr("每开一箱，今晚下一箱更贵。次日恢复首箱价。")
	for index in odds_labels.size():
		var chance = float(quote.odds[index])
		var amount = "%.2f%%" % chance if chance > 0.0 and chance < 1.0 else "%.1f%%" % chance
		odds_labels[index].text = "%s  %s" % [Trophies.grade_name(index+1), amount]
	var price = int(quote.gold)
	var empty = int(quote.remaining) == 0
	buy.disabled = opening or empty or sim.gold < price
	buy.text = tr("开箱中…") if opening else (tr("奖杯已集齐") if empty else tr("打开盲盒 · %d 金币") % price)
	buy.tooltip_text = (tr("还差 %d 金币") % (price - sim.gold)) if sim.gold < price and not empty and not opening else ledger.tooltip_text
	skip.visible = opening
	bag.disabled = opening
	place.hide()
	if opening:
		prize.text = tr("奖杯即将揭晓")
		prize.add_theme_color_override("font_color", Style.INK)
		effect.text = tr("即使关闭页面，开出的奖杯也会留在背包。")
	elif sim.last_trophy_id.is_empty():
		prize.text = tr("展廊收藏")
		prize.add_theme_color_override("font_color", Style.INK)
		effect.text = tr("开出未收藏的奖杯，放进展廊即可生效。")
	else:
		var trophy = sim.relic_defs[sim.last_trophy_id]
		prize.text = tr("%s · %s品质") % [tr(trophy.name), Trophies.grade_name(int(trophy.rarity))]
		prize.add_theme_color_override("font_color", Trophies.grade_color(int(trophy.rarity)))
		effect.text = Trophies.description(trophy)
		var id = "trophy_" + sim.last_trophy_id
		var facility = Grid.find(sim.layout, id)
		place.visible = not Grid.placed(facility)
		place.disabled = Grid.facilities(sim.layout, "trophy").size() >= int(sim.attributes.relic_slots)
		place.tooltip_text = tr("展示位已满，可在奖杯背包收起现有奖杯") if place.disabled else tr("到展廊选择展示位置")

func animate_opening(result: Dictionary, offer: Dictionary) -> void:
	opening = true
	refresh(offer)
	reel.open_coffer(sim.relic_defs[result.id])

func _finish_opening() -> void:
	opening = false
	refresh()

func _place() -> void:
	if not opening and not sim.last_trophy_id.is_empty():
		place_requested.emit("trophy_" + sim.last_trophy_id)

class Reel extends Control:
	signal opened

	static var tick_sound: AudioStreamWAV
	static var award_sounds: Dictionary = {}

	var font: Font
	var pending_reward: Dictionary = {}
	var reward: Dictionary = {}
	var rolling := false
	var motion: Tween
	var click := AudioStreamPlayer.new()
	var chime := AudioStreamPlayer.new()
	const CASE = preload("res://assets/interface/hextech-coffer.webp")
	var stage_box: StyleBox
	var lid_phase := 0.0:
		set(value):
			lid_phase = value
			queue_redraw()
	var shine := 1.0:
		set(value):
			shine = value
			queue_redraw()

	func _ready() -> void:
		name = "TrophyReel"
		font = Style.font()
		stage_box = Style.art_plate()
		resized.connect(queue_redraw)
		click.volume_db = -21.0
		chime.volume_db = -13.0
		add_child(click)
		add_child(chime)

	func show_reward(item: Dictionary) -> void:
		reward = item
		shine = 1.0

	func open_coffer(item: Dictionary) -> void:
		if rolling: return
		if motion != null and motion.is_valid(): motion.kill()
		pending_reward = item
		reward = {}
		rolling = true
		lid_phase = 0.0
		if tick_sound == null: tick_sound = _tone(0)
		click.stream = tick_sound
		motion = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		motion.tween_property(self, "lid_phase", 1.0, .46)
		motion.tween_callback(click.play)
		motion.tween_property(self, "lid_phase", 2.0, .57)
		motion.tween_property(self, "lid_phase", 3.0, .49)
		motion.tween_interval(.20)
		motion.tween_callback(finish)

	func finish() -> void:
		if not rolling: return
		rolling = false
		if motion != null and motion.is_valid(): motion.kill()
		show_reward(pending_reward)
		pending_reward = {}
		shine = 0.0
		var grade = int(reward.rarity)
		if not award_sounds.has(grade): award_sounds[grade] = _tone(grade)
		chime.stream = award_sounds[grade]
		chime.play()
		motion = create_tween()
		motion.tween_property(self, "shine", 1.0, .58 + .17 * grade)
		opened.emit()

	static func _tone(grade: int) -> AudioStreamWAV:
		const RATE := 16000
		var duration = .041 if grade == 0 else .21 + grade * .073
		var audio = AudioStreamWAV.new()
		audio.mix_rate = RATE
		audio.format = AudioStreamWAV.FORMAT_16_BITS
		var count = ceili(duration * RATE)
		var bytes := PackedByteArray()
		bytes.resize(count * 2)
		for index in count:
			var t = float(index) / RATE
			var envelope = minf(1.0, t * 220.0) * pow(1.0 - t / duration, 2.3)
			var value = sin(TAU * (630.0 if grade == 0 else 330.0 + grade * 71.0) * t)
			if grade > 0:
				var sweep = maxf(0.0, t - .032)
				value = value * .58 + sin(TAU * (495.0 + grade * 78.0) * sweep) * .37
				if grade > 2: value += sin(TAU * (720.0 + grade * 67.0) * maxf(0.0, t - .082)) * .17
			bytes.encode_s16(index * 2, roundi(value * envelope * 16000.0))
		audio.data = bytes
		return audio

	func _draw() -> void:
		if font==null or size.x<2.:return
		draw_style_box(stage_box,Rect2(Vector2.ZERO,size))
		var selection := lid_phase/3.0 if rolling else (0. if reward.is_empty() else 1.)
		var phase := clampf(selection*3.,0.,3.)
		var low := floori(phase)
		var high := mini(3,low+1)
		var blend := smoothstep(.12,.86,phase-low)
		var h:=minf(size.y*.94,size.x*.44)
		var reveal := 0.0 if reward.is_empty() else smoothstep(0.0, .53, shine)
		var xpos := size.x * lerpf(.49, .36, reveal)
		var center:=Vector2(xpos,size.y*.51)
		var dst:=Rect2(center-Vector2.ONE*h*.5,Vector2.ONE*h)
		draw_texture_rect_region(CASE,dst,Rect2(low*256,0,256,256),Color(1,1,1,1.-blend))
		if high!=low and blend>0.:
			draw_texture_rect_region(CASE,dst,Rect2(high*256,0,256,256),Color(1,1,1,blend))
		if not reward.is_empty(): _draw_reward(Vector2(size.x*.69,size.y*.53))
	func _draw_reward(center: Vector2) -> void:
		var grade = int(reward.rarity)
		var tint = Trophies.grade_color(grade)
		var ease_out = 1.0 - pow(1.0 - shine, 3.0)
		var still = minf(1.0, shine * 3.0)
		var ring_count = 1 + grade
		for i in ring_count:
			var radius = 48.0 + i * (12.0 if grade < 4 else 13.5) + (1.0 - still) * 11.0
			var glow_tint = Color(Trophies.PRISM[i % Trophies.PRISM.size()]) if grade == 5 else tint
			draw_circle(center, radius, Color(glow_tint, (.13 + .019 * grade) * still), false, 1.2, true)
			if i > 0 and grade >= 3:
				draw_arc(center, radius, i * .92 - shine * 1.5, i * .92 - shine * 1.5 + 1.18, 24, Color(glow_tint, .51 * still), 2, true)
		if grade >= 4:
			_draw_rays(center, grade, ease_out)
		var particle_count = [7, 14, 25, 43, 64][grade - 1]
		for i in particle_count:
			var angle = i * 2.39996
			var distance = (39.0 + float(i * 37 % 70)) * (ease_out * .76 + .24)
			var point = center + Vector2.from_angle(angle) * distance
			var glitter = Color(Trophies.PRISM[i % Trophies.PRISM.size()]) if grade == 5 else tint.lightened(.2)
			var opacity = (.28 + .44 * sin(angle + shine * 7.0) ** 2.0) * still
			if i % 3 == 0:
				_diamond(point, 2.0 + .22 * grade, Color(glitter, opacity))
			else:
				draw_circle(point, 1.05 + .17 * grade, Color(glitter, opacity), true, -1, true)
		_diamond(center, 47, Color(tint, .13))
		draw_set_transform(center + Vector2(0, -6), 0.0, Vector2.ONE * (1.04 + ease_out * .81))
		TrophyArt.paint(self, reward)
		draw_set_transform(Vector2.ZERO)
		_centered(tr("%s品质") % Trophies.grade_name(grade), Vector2(center.x, size.y - 38), 14, tint, 160)

	func _draw_rays(center: Vector2, grade: int, progress: float) -> void:
		var count = 11 if grade == 4 else 16
		for index in count:
			var angle = TAU * float(index) / count + progress * .32
			var tint = Style.GOLD if grade == 4 else Color(Trophies.PRISM[index % Trophies.PRISM.size()])
			var start = center + Vector2.from_angle(angle) * 29.0
			var ray = Vector2.from_angle(angle) * lerpf(78.0, 170.0, progress)
			draw_colored_polygon(PackedVector2Array([start, start + ray + ray.orthogonal() * .042, start + ray - ray.orthogonal() * .057]), Color(tint, .10 if grade == 4 else .14))

	func _diamond(center: Vector2, radius: float, tint: Color) -> void:
		draw_colored_polygon(PackedVector2Array([center + Vector2.UP * radius, center + Vector2.RIGHT * radius, center + Vector2.DOWN * radius, center + Vector2.LEFT * radius]), tint)

	func _centered(label: String, at: Vector2, font_size: int, tint: Color, width: float) -> void:
		var step = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(font, at - Vector2(minf(step, width) * .5, 0.0), label, HORIZONTAL_ALIGNMENT_LEFT, width, font_size, tint)
