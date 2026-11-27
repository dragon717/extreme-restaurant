extends VBoxContainer

signal accepted(lineup: Array)
signal cancelled

const Roster = preload("res://scripts/core/crew_roster.gd")
const Style = preload("res://scripts/ui/style.gd")
const Icon = preload("res://scripts/ui/ui_icon.gd")

var profile: RefCounted
var lineup: Array = []
var cards := {}
var editing_group := -1
var management_only := false
var initial_lineup: Array = []
var shift_only := false
var helper_staff := {}
var capacity := {"chef":2,"waiter":4}
var helper_controls


func _ready() -> void:
	profile = Roster.new("--ui-test" in OS.get_cmdline_user_args())
	%Confirm.pressed.connect(_confirm)
	%Cancel.pressed.connect(cancelled.emit)
	%Apply.pressed.connect(_apply_group)
	%Clear.pressed.connect(_clear_selection)
	%SaveGroup.pressed.connect(_save_group)
	%NewGroup.pressed.connect(_new_group)
	%GroupList.item_selected.connect(func(_index): _update())
	Style.accent_button(%Confirm)
	lineup = initial_lineup.duplicate(true)
	if not management_only:
		helper_controls = preload("res://scripts/ui/helper_assignment.gd").new()
		if has_node("%HelperMount"):
			get_node("%HelperMount").add_child(helper_controls)
		else:
			add_child(helper_controls)
			move_child(helper_controls,%Pool.get_index())
	%Title.text = tr("编辑并保存局外分组") if management_only else (tr("安排今天的员工岗位") if shift_only else tr("选出本局的五位特色员工"))
	%Confirm.visible = not management_only
	%GroupTools.visible = not shift_only
	var available: Array = lineup.map(func(entry): return entry.id) if shift_only and not lineup.is_empty() else profile.unlocked
	for id in available: _add_candidate(str(id))
	_refresh_groups()
	_update()
	if not cards.is_empty(): cards.values()[0].pick.grab_focus()

func _add_candidate(id: String) -> void:
	var definition: Dictionary = Roster.PROFILES[id]
	var card := Style.card()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", Style.inset(8,10))
	%Pool.add_child(card)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	card.add_child(body)
	var row := HBoxContainer.new()
	body.add_child(row)
	var insignia := TextureRect.new()
	insignia.texture = load(definition.badge)
	insignia.custom_minimum_size = Vector2(31,31)
	insignia.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	insignia.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	insignia.tooltip_text = tr(definition.reference_skill) if not definition.reference_skill.is_empty() else tr(definition.name)
	row.add_child(insignia)
	var check := Icon.make("check", Style.GOLD, 16)
	check.visible = false
	var pick := Style.button(tr(definition.name))
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.toggle_mode = true
	pick.add_theme_stylebox_override("pressed", Style.wash(.24))
	pick.pressed.connect(_toggle.bind(id))
	row.add_child(pick)
	row.add_child(check)
	var position := Style.button("")
	position.pressed.connect(_swap_role.bind(id))
	position.visible = definition.roles.size() > 1
	row.add_child(position)
	var caption := Style.text("", 15, Style.INK)
	body.add_child(caption)
	if not definition.title.is_empty(): body.add_child(Style.text(tr(definition.title),13,Style.GOLD))
	body.add_child(Style.text(definition.copy, 13, Style.MUTED, true))
	cards[id] = {"pick":pick, "position":position, "caption":caption, "check":check}

func _index(id: String) -> int:
	return lineup.find_custom(func(entry): return entry.id == id)

func _toggle(id: String) -> void:
	var index := _index(id)
	if index >= 0:
		lineup.remove_at(index)
	elif lineup.size() < Roster.LIMIT:
		lineup.append({"id":id,"role":Roster.PROFILES[id].roles[0]})
	_update()

func _swap_role(id: String) -> void:
	var index := _index(id)
	if index < 0: return
	lineup[index].role = "waiter" if lineup[index].role == "chef" else "chef"
	_update()

func _refresh_groups() -> void:
	%GroupList.clear()
	%GroupList.add_item(tr("选择已保存分组"))
	for group in profile.groups: %GroupList.add_item(group.name)
	%GroupList.select(0)

func _apply_group() -> void:
	if %GroupList.selected <= 0: return
	editing_group = %GroupList.selected - 1
	var group: Dictionary = profile.groups[editing_group]
	lineup = group.crew.duplicate(true)
	%GroupName.text = group.name
	_status("")
	_update()

func _clear_selection() -> void:
	lineup.clear()
	_new_group()
	if not cards.is_empty(): cards.values()[0].pick.grab_focus()
	_update()

func _new_group() -> void:
	editing_group = -1
	%GroupName.clear()
	%GroupList.select(0)
	_status("")
	%GroupName.grab_focus()
	_update()

func _save_group() -> void:
	var before: int = profile.groups.size()
	var error: String = profile.save_group(editing_group, %GroupName.text, lineup)
	if not error.is_empty():
		_status(error, true)
		return
	if profile.groups.size() > before: editing_group = profile.groups.size() - 1
	_refresh_groups()
	%GroupList.select(editing_group + 1)
	_status(tr("分组已保存。"))
	_update()

func _confirm() -> void:
	if not Roster.valid(lineup, profile.unlocked) and not (shift_only and lineup.is_empty() and initial_lineup.is_empty()): return
	accepted.emit(lineup.duplicate(true))

func _update() -> void:
	var chefs := Roster.by_role(lineup, "chef").size()
	var waiters := lineup.size() - chefs
	%Counts.text = tr("已选 %d / 5    厨师 %d / 2    服务员 %d / 4") % [lineup.size(), chefs, waiters]
	%Counts.add_theme_color_override("font_color", Style.GOLD if chefs <= 2 and waiters <= 4 else Style.RED)
	var ready := Roster.valid(lineup, profile.unlocked)
	if ready: %Counts.text += "    " + (tr("小兵补前厅") if chefs == 2 else tr("小兵补后厨"))
	var manual: Array[String] = []
	if _index("kilnkeeper") >= 0: manual.append(tr("连灶飞火"))
	if _index("ferrier") >= 0: manual.append(tr("河道急送"))
	%Skills.visible = not manual.is_empty()
	%Skills.text = tr("白天手动应急 · %s") % " / ".join(manual)
	%Skills.add_theme_color_override("font_color", Style.MUTED)
	var cooperation: Array[String] = []
	var kitchen := Roster.by_role(lineup, "chef")
	var floor_staff := Roster.by_role(lineup, "waiter")
	if "ferrier" in floor_staff and "riverclaw" in floor_staff:
		cooperation.append(tr("前厅羁绊 · 希维尔与峡谷迅捷蟹同班，迅捷蟹的急送余速延长 1 秒。"))
	if "kilnkeeper" in kitchen and "hearthling" in kitchen:
		cooperation.append(tr("后厨羁绊 · 布兰德与安妮相邻备锅时，安妮的锅可提前点燃。"))
	%Cooperation.text = "\n".join(cooperation)
	%Cooperation.visible = not cooperation.is_empty()
	%Cooperation.add_theme_color_override("font_color", Style.GREEN)
	if helper_controls != null: helper_controls.roster(lineup,capacity,helper_staff)
	%Confirm.disabled = not ready and not (shift_only and lineup.is_empty() and initial_lineup.is_empty())
	%SaveGroup.disabled = not ready
	%Apply.disabled = %GroupList.selected <= 0
	_update_cards()

func _update_cards() -> void:
	for id in cards:
		var card: Dictionary = cards[id]
		var picked := _index(str(id))
		var definition: Dictionary = Roster.PROFILES[id]
		var role: String = str(lineup[picked].role) if picked >= 0 else definition.roles[0]
		var role_title := tr("厨师") if role == "chef" else tr("服务员")
		card.pick.set_pressed_no_signal(picked >= 0)
		card.check.visible = picked >= 0
		card.pick.disabled = picked < 0 and lineup.size() >= Roster.LIMIT
		card.position.text = role_title + " ↔"
		card.position.disabled = picked < 0
		card.caption.text = "%s  ·  %s" % [role_title, tr(definition.skill)]

func _status(message: String, error := false) -> void:
	%Status.text = message
	%Status.visible = not message.is_empty()
	%Status.add_theme_color_override("font_color", Style.RED if error else Style.GREEN)
