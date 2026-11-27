extends Node2D

const POINTER_DEVICE := -7
const DEADZONE := .24

signal pointer_canceled

var device := -1
var point := Vector2.ZERO
var holding := false
var keyboard_pointer := false
var left_stick := Vector2.ZERO
var right_stick := Vector2.ZERO

func _ready() -> void:
	hide()
	Input.joy_connection_changed.connect(_connection_changed)

func handle(event: InputEvent, game: Control) -> void:
	if event is InputEventMouse and event.device == POINTER_DEVICE: return
	if (event is InputEventMouseMotion and event.relative.length_squared() > 1.0) or event is InputEventMouseButton or event is InputEventScreenTouch:
		release_pointer()
		keyboard_pointer = false
		hide()
		return
	if event is InputEventKey:
		_keyboard(event, game.world)
		return
	if event is InputEventJoypadMotion:
		if event.axis >= JOY_AXIS_LEFT_X and event.axis <= JOY_AXIS_RIGHT_Y:
			get_viewport().set_input_as_handled()
		if absf(event.axis_value) > DEADZONE or device == event.device:
			_use_device(event.device)
			match event.axis:
				JOY_AXIS_LEFT_X: left_stick.x = event.axis_value
				JOY_AXIS_LEFT_Y: left_stick.y = event.axis_value
				JOY_AXIS_RIGHT_X: right_stick.x = event.axis_value
				JOY_AXIS_RIGHT_Y: right_stick.y = event.axis_value
		return
	if not event is InputEventJoypadButton: return
	if event.pressed:
		if keyboard_pointer: release_pointer()
		keyboard_pointer = false
		_use_device(event.device)
	if event.device != device: return
	match event.button_index:
		JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT:
			if not event.pressed: return
			release_pointer()
			hide()
			if game._focus_controls(): get_viewport().set_input_as_handled()
		JOY_BUTTON_A:
			if visible or holding:
				get_viewport().set_input_as_handled()
				holding = event.pressed
				_send_button(event.pressed, point)
			elif event.pressed:
				game._focus_controls()
		JOY_BUTTON_B, JOY_BUTTON_START, JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER:
			get_viewport().set_input_as_handled()
			if not event.pressed: return
			match event.button_index:
				JOY_BUTTON_B:
					release_pointer()
					game._go_back()
				JOY_BUTTON_START:
					if game.modal_kind == "settings": game._go_back()
					elif game.modal_layer == null: game._show_settings()
				JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER:
					if not game.world.camera_input_enabled: return
					var target: Vector2 = point if visible else game.world.size * .5
					game.world.zoom_at(target, 1.1 if event.button_index == JOY_BUTTON_RIGHT_SHOULDER else 1.0 / 1.1)

func move(delta: float, world: Control) -> void:
	if device < 0 or keyboard_pointer: return
	var look := _analog(left_stick)
	if look != Vector2.ZERO and world.camera_input_enabled:
		world.pan_camera(-look * delta * 400.0)
	var direction := _analog(right_stick)
	if direction == Vector2.ZERO: return
	_move_pointer(direction * delta * 650.0)

func _keyboard(event: InputEventKey, world: Control) -> void:
	var key := event.keycode if event.keycode != KEY_NONE else event.physical_keycode
	if event.pressed and key in [KEY_ESCAPE, KEY_TAB]:
		if keyboard_pointer:
			release_pointer()
			keyboard_pointer = false
			hide()
		return
	if not world.camera_input_enabled or get_viewport().gui_get_focus_owner() is LineEdit: return
	var direction := Vector2.ZERO
	if event.shift_pressed and event.pressed:
		match key:
			KEY_LEFT: direction = Vector2.LEFT
			KEY_RIGHT: direction = Vector2.RIGHT
			KEY_UP: direction = Vector2.UP
			KEY_DOWN: direction = Vector2.DOWN
	if direction != Vector2.ZERO:
		get_viewport().set_input_as_handled()
		if not keyboard_pointer:
			release_pointer()
			keyboard_pointer = true
		_move_pointer(direction * world._unit())
	elif keyboard_pointer and visible and key in [KEY_ENTER, KEY_KP_ENTER]:
		get_viewport().set_input_as_handled()
		if event.echo: return
		holding = event.pressed
		_send_button(event.pressed, point)

func _move_pointer(amount: Vector2) -> void:
	var bounds := get_viewport_rect()
	var previous := point if visible else bounds.get_center()
	point = (previous + amount).clamp(bounds.position + Vector2.ONE, bounds.end - Vector2.ONE)
	show()
	position = point
	var motion := InputEventMouseMotion.new()
	motion.device = POINTER_DEVICE
	motion.position = point
	motion.global_position = point
	motion.relative = point - previous
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT if holding else 0
	get_viewport().push_input(motion, true)

func _analog(stick: Vector2) -> Vector2:
	var magnitude := stick.length()
	if magnitude <= DEADZONE: return Vector2.ZERO
	return stick / magnitude * inverse_lerp(DEADZONE, 1.0, minf(magnitude, 1.0))

func _use_device(next: int) -> void:
	if device == next: return
	release_pointer()
	left_stick = Vector2.ZERO
	right_stick = Vector2.ZERO
	device = next

func _connection_changed(changed: int, connected: bool) -> void:
	if not connected and changed == device:
		_use_device(-1)
		hide()

func release_pointer() -> void:
	if not holding: return
	holding = false
	pointer_canceled.emit()
	_send_button(false, Vector2(-64, -64))

func _send_button(pressed: bool, at: Vector2) -> void:
	var click := InputEventMouseButton.new()
	click.device = POINTER_DEVICE
	click.position = at
	click.global_position = at
	click.button_index = MOUSE_BUTTON_LEFT
	click.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	click.pressed = pressed
	get_viewport().push_input.call_deferred(click, true)

func _draw() -> void:
	draw_circle(Vector2.ZERO, 10, Color("192e35"))
	draw_arc(Vector2.ZERO, 8, 0, TAU, 32, Color("ffe0a4"), 2.0, true)
	draw_circle(Vector2.ZERO, 2, Color("ffe0a4"))
