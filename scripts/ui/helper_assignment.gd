extends VBoxContainer
const Minions=preload("res://scripts/core/minion_staff.gd")
const Crew=preload("res://scripts/core/crew_roster.gd")
const Style=preload("res://scripts/ui/style.gd")
var assignment := {}
var posts: Array = []
var post := OptionButton.new()
var kind := OptionButton.new()
var trait_label := Label.new()

func _ready() -> void:
	add_theme_constant_override("separation",8)
	add_child(Style.text("补位小兵",18,Style.GOLD))
	var row:=HBoxContainer.new()
	add_child(row)
	for choice in [post,kind]:
		choice.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		choice.custom_minimum_size=Vector2(140,40)
		row.add_child(choice)
	for id in Minions.KINDS: kind.add_icon_item(load("res://assets/crew/minion-%s-badge.webp"%id),tr(Minions.NAMES[id]))
	kind.add_theme_constant_override("icon_max_width",25)
	add_child(trait_label)
	trait_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	trait_label.add_theme_color_override("font_color",Style.MUTED)
	post.item_selected.connect(func(_i): _show_post())
	kind.item_selected.connect(func(i):
		if posts.is_empty(): return
		var selected: Dictionary=posts[post.selected]
		Minions.set_slot(assignment,selected.role,selected.index,Minions.KINDS[i])
		_show_post()
	)

func roster(lineup: Array,capacity: Dictionary,choices: Dictionary) -> void:
	assignment=choices
	var old := post.selected
	posts.clear();post.clear()
	for role in ["chef","waiter"]:
		var count:=int(capacity[role])-Crew.by_role(lineup,role).size()
		for i in range(maxi(0,count)):
			posts.append({"role":role,"index":i})
			post.add_item(tr("后厨补位 %d" if role=="chef" else "前厅补位 %d") % (i+1))
	if not posts.is_empty():
		post.select(clampi(old,0,posts.size()-1))
		_show_post()
	else: trait_label.text=tr("当前岗位已排满。")
	kind.disabled=posts.is_empty()
	post.disabled=posts.size()<=1

func _show_post() -> void:
	var selected: Dictionary=posts[post.selected]
	var species:=Minions.at(assignment,selected.role,selected.index)
	kind.select(Minions.KINDS.find(species))
	trait_label.text=tr(Minions.TRAITS[selected.role][species])
