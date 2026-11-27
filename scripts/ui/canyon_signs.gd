extends Control

signal landmark_pressed(id: String)
const Plan = preload("res://scripts/visuals/canyon_plan.gd")
# Label the frontage rather than occluding the painted roof.
const ANCHORS = {"tavern":Vector2(553,628),"freight":Vector2(320,300),"supply":Vector2(1023,427),"workshop":Vector2(1261,317),"gallery":Vector2(1425,485),"dock":Vector2(1440,846)}

func _ready() -> void:
	for button: TextureButton in get_children():
		var id := str(button.name)
		button.get_node("Caption").text = tr(Plan.LABELS[id])
		button.accessibility_name = tr(Plan.LABELS[id])
		button.pressed.connect(func(): landmark_pressed.emit(id))
		button.focus_entered.connect(func(): button.modulate = Color(1.24,1.19,1.06))
		button.focus_exited.connect(func(): button.modulate = Color.WHITE)
		button.mouse_entered.connect(func(): button.modulate = Color(1.20,1.16,1.07))
		button.mouse_exited.connect(func(): button.modulate = Color.WHITE if not button.has_focus() else Color(1.24,1.19,1.06))

func project(origin: Vector2, unit: float) -> void:
	for button: TextureButton in get_children():
		var at := origin + (Plan.from_art(ANCHORS[str(button.name)]) + Vector2(.5,.5)) * unit
		var width := clampf(size.x * .102, 108, 165)
		button.size = Vector2(width, width * .52)
		button.position = at - button.size * Vector2(.5,.3)

func focus_tavern() -> void:
	if is_visible_in_tree(): $tavern.grab_focus()
