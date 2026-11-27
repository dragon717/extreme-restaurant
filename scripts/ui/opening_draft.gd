extends "res://scripts/ui/crew_select.gd"
## A pick is a preview until the player adds it. The five-person lock and saved
## groups use the same roster validation as nightly staffing.
const ART := {"kilnkeeper":"Brand","ovenhand":"Pantheon","ferrier":"Sivir","riverclaw":"Scuttler","mosskeeper":"Gromp","hearthling":"Annie"}
var chapter_caption := ""
var inspected := ""
var squad: Array[Button] = []
var portrait_motion: Tween

func _ready() -> void:
	theme = Style.list_theme()
	%Portrait.material = %Portrait.material.duplicate()
	%Portrait.resized.connect(_fit_portrait)
	_fit_portrait()
	%Chapter.text = chapter_caption
	for i in range(Roster.LIMIT):
		var slot := Style.button("—")
		slot.custom_minimum_size = Vector2(57,53)
		slot.expand_icon = true
		slot.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		Style.quiet_button(slot)
		slot.pressed.connect(_inspect_slot.bind(i))
		%Squad.add_child(slot)
		squad.append(slot)
	super()
	%Title.text = tr("选择本局英雄")
	if not TranslationServer.get_locale().begins_with("en"):
		var serif := preload("res://assets/fonts/CanyonTitleSerif.ttf")
		%Title.add_theme_font_override("font",serif)
		%HeroName.add_theme_font_override("font",serif)

	%Confirm.text = tr("锁定阵容")
	%Pick.pressed.connect(func(): _toggle(inspected))
	Style.quiet_button(%Pick,true)
	%Position.pressed.connect(func(): _swap_role(inspected))
	%EditGroups.pressed.connect(func(): _show_groups(not %GroupDrawer.visible))
	%HelperButton.pressed.connect(func():
		var show_helper: bool = not %HelperMount.visible
		_show_groups(false)
		%HelperMount.visible=show_helper
		%Pool.visible=not show_helper
		%PoolLabel.visible=not show_helper
		if show_helper: helper_controls.kind.grab_focus()
		else: %HelperButton.grab_focus()
	)
	%HelperMount.add_theme_stylebox_override("panel",Style.art_plate())
	%Backing.add_theme_stylebox_override("panel",Style.art_plate())
	%GroupDrawer.hide()
	if not cards.is_empty(): _inspect(str(cards.keys()[0]))

func _show_groups(opened: bool) -> void:
	%HelperMount.hide()
	%GroupDrawer.visible = opened
	%Pool.visible = not opened
	%PoolLabel.visible = not opened
	if opened: %GroupList.grab_focus()
	else: %EditGroups.grab_focus()

func _apply_group() -> void:
	super()
	_show_groups(false)

func _clear_selection() -> void:
	_show_groups(false)
	super()

func _fit_portrait() -> void:
	%Portrait.material.set_shader_parameter("panel_size",%Portrait.size)

func _icon_for(id: String) -> Texture2D:
	var name_key: String = ART[id]
	if name_key in ["Scuttler","Gromp"]: return load(Roster.PROFILES[id].badge)
	return load("res://assets/draft/%s-square.webp" % name_key)

func _add_candidate(id: String) -> void:
	var tile := VBoxContainer.new()
	tile.add_theme_constant_override("separation",0)
	%Pool.add_child(tile)
	var button := Style.button("")
	button.custom_minimum_size = Vector2(90,72)
	Style.quiet_button(button)
	var portrait := TextureRect.new()
	portrait.texture = _icon_for(id)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(portrait)
	portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait.offset_left = 2
	portrait.offset_top = 4
	portrait.offset_right = -2
	portrait.offset_bottom = -4
	button.accessibility_name = tr(Roster.PROFILES[id].name)
	button.focus_entered.connect(_inspect.bind(id))
	button.pressed.connect(_inspect.bind(id))
	tile.add_child(button)
	var legend := Style.text(tr(Roster.PROFILES[id].name),14,Style.INK)
	legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tile.add_child(legend)
	cards[id] = {"pick":button,"caption":legend}

func _inspect_slot(index: int) -> void:
	if index < lineup.size(): _inspect(str(lineup[index].id))

func _inspect(id: String) -> void:
	if not cards.has(id): return
	var changed := inspected != id
	inspected = id
	var staff: Dictionary = Roster.PROFILES[id]
	%HeroTitle.text = tr(staff.title) if not staff.title.is_empty() else tr("野怪")
	%HeroName.text = tr(staff.name)
	%SkillIcon.texture = load(staff.badge)
	%Skill.text = tr(staff.skill)
	%Description.text = tr(staff.copy)
	var is_beast: bool = str(ART[id]) in ["Scuttler","Gromp"]
	%Portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED if is_beast else TextureRect.STRETCH_KEEP_ASPECT_COVERED
	%Portrait.texture = load("res://assets/draft/%s-portrait.webp" % ART[id])
	if changed:
		if portrait_motion != null: portrait_motion.kill()
		%Portrait.modulate.a = .45
		portrait_motion = create_tween()
		portrait_motion.tween_property(%Portrait,"modulate:a",1.,.20)
	_update_cards()

func _update_cards() -> void:
	for i in range(squad.size()):
		var slot := squad[i]
		slot.disabled = i >= lineup.size()
		slot.icon = null if slot.disabled else _icon_for(lineup[i].id)
		slot.text = "—" if slot.disabled else ""
		slot.tooltip_text = "" if slot.disabled else tr(Roster.PROFILES[lineup[i].id].name)
	for id in cards:
		var selected := _index(id) >= 0
		cards[id].caption.text = ("✓ " if selected else "") + tr(Roster.PROFILES[id].name)
		cards[id].caption.modulate = Style.GOLD if id == inspected else Color.WHITE
		cards[id].pick.modulate = Color.WHITE if id == inspected or selected else Color(.79,.84,.89)
	if inspected.is_empty(): return
	var index := _index(inspected)
	var staff: Dictionary = Roster.PROFILES[inspected]
	%Pick.text = tr("移出阵容") if index >= 0 else tr("加入阵容")
	%Pick.disabled = index < 0 and lineup.size() >= Roster.LIMIT
	%Position.visible = staff.roles.size() > 1 and index >= 0
	if %Position.visible: %Position.text = (tr("厨师") if lineup[index].role == "chef" else tr("服务员")) + " ↔"

func _input(event: InputEvent) -> void:
	if (%GroupDrawer.visible or %HelperMount.visible) and event.is_action_pressed("ui_cancel"):
		_show_groups(false)
		get_viewport().set_input_as_handled()
